# One row per Near-Miss repair attempt, including failures — "the LLM could
# not fix it within budget" is a data point for the study, not an error.
# Grading state/score of an accepted repair lives on the shadow Submission
# (repaired_submission), never duplicated here.
# See docs/superpowers/specs/2026-07-30-near-miss-grading-design.md.
class SubmissionRepair < ApplicationRecord
  enum :status, {pending: 0, processing: 1, accepted: 2, over_budget: 3, no_change: 4, failed: 5}

  FIX_CATEGORIES = %w[io_format parsing syntax boundary logic other].freeze

  # Shadow judge states that are real grading outcomes. compilation_error IS
  # one (the repair broke the build — damage data); grader_error and
  # in-flight states are not grades at all, yet their points column reads 0 —
  # counting those zeros as grades made the void a68_final run look like
  # mass model damage ("0 rescues / 63 negative gaps").
  GRADED_SHADOW_STATUSES = %w[done compilation_error].freeze

  belongs_to :original_submission, class_name: 'Submission'
  belongs_to :repaired_submission, class_name: 'Submission', optional: true

  serialize :rounds_log, coder: JSON, type: Array

  validates :budget_lines, :budget_chars, numericality: {greater_than: 0}
  validates :fix_category, inclusion: {in: FIX_CATEGORIES}, allow_nil: true

  # True when the attempt's shadow has a real judge outcome; an accepted
  # attempt whose shadow lacks one is "ungradeable" and must stay out of
  # every gap/rescue statistic.
  def shadow_graded?
    accepted? && GRADED_SHADOW_STATUSES.include?(repaired_submission&.status)
  end

  # Batch target selection (rake near_miss:repair). Returns ids of
  # submissions eligible for repair:
  #  * regular (never repair a shadow), non-viva (spec D8), graded
  #  * "below full marks" = points < 100 on a non-raw_sum live dataset
  #    (the grader normalizes sum/group_min to 100; raw_sum problems have
  #    no defined full score and are skipped — mirror of the canonical
  #    activity_query pattern in report_controller.rb)
  #  * scope: 'latest' = latest submission per (user, problem), kept only
  #    if that latest one is below full; 'all' = every below-full submission
  def self.batch_targets(problems:, users:, scope: 'latest', min_score: nil, max_score: nil)
    base = Submission.regular
      .where(problem: problems, user: users)
      .where(status: [Submission.statuses[:done], Submission.statuses[:compilation_error]])
    viva_language = Language.find_by(name: 'viva')
    base = base.where.not(language: viva_language) if viva_language

    if scope == 'latest'
      last_ids = base.group(:user_id, :problem_id).pluck(Arel.sql('MAX(submissions.id)'))
      base = Submission.where(id: last_ids)
    end

    below_full = base
      .joins(:problem)
      .joins('LEFT JOIN datasets live_ds ON live_ds.id = problems.live_dataset_id')
      .where('live_ds.score_type IS NOT NULL AND live_ds.score_type <> ?', Dataset.score_types[:raw_sum])
      .where('submissions.points < 100')
    below_full = below_full.where('submissions.points >= ?', min_score) if min_score.present?
    below_full = below_full.where('submissions.points <= ?', max_score) if max_score.present?
    below_full.pluck(:id)
  end

  # Creates pending attempt rows and enqueues one repair job per target.
  # Idempotent per (original_submission, run_label): re-running the same
  # RUN label skips submissions that already have an attempt row, so a
  # crashed batch can be resumed by re-running the same command.
  def self.enqueue_batch!(submission_ids:, budget_lines:, budget_chars:, rounds:, run_label:, model_key: nil)
    enqueued = 0
    skipped  = 0
    submission_ids.each do |sid|
      if exists?(original_submission_id: sid, run_label: run_label)
        skipped += 1
        next
      end
      repair = create!(original_submission_id: sid, status: :pending,
                       budget_lines: budget_lines, budget_chars: budget_chars,
                       run_label: run_label)
      Llm::SubmissionRepairJob.perform_later(Submission.find(sid), repair: repair,
                                             rounds: rounds, model_key: model_key)
      enqueued += 1
    end
    {enqueued: enqueued, skipped: skipped}
  end

  # Aggregated per-run, per-problem study report.
  # {run_label => {problem_name => {targets:, statuses: {..}, ungradeable:,
  #   rescued:, rescue_rate:, mean_gap:, median_gap:, categories: {..},
  #   sizes: [changed_chars,...], compliance: {round => {within:, total:}},
  #   tokens_in:, tokens_out:, cost:}}}
  # Gap/rescue stats read only shadows with a real judge outcome
  # (GRADED_SHADOW_STATUSES); accepted attempts whose shadow has none are
  # reported as `ungradeable`, never as 0-point grades.
  def self.report_for(run_labels)
    attempts = where(run_label: run_labels)
               .includes(original_submission: :problem)
               .includes(:repaired_submission)
    result = {}
    attempts.group_by(&:run_label).each do |label, rows|
      per_problem = {}
      rows.group_by { |r| r.original_submission.problem.name }.each do |pname, prows|
        accepted_rows = prows.select(&:accepted?)
        graded_rows   = accepted_rows.select(&:shadow_graded?)
        gaps = graded_rows.map { |r| r.repaired_submission.points.to_f - r.original_submission.points.to_f }
        rescued = gaps.count(&:positive?)
        compliance = Hash.new { |h, k| h[k] = {within: 0, total: 0} }
        prows.each do |r|
          Array(r.rounds_log).each do |entry|
            next unless entry['changed_lines']
            c = compliance[entry['round']]
            c[:total] += 1
            c[:within] += 1 if entry['gate'] == 'accepted'
          end
        end
        per_problem[pname] = {
          targets:    prows.size,
          statuses:   prows.group_by(&:status).transform_values(&:size),
          ungradeable: accepted_rows.size - graded_rows.size,
          rescued:    rescued,
          rescue_rate: prows.size.zero? ? 0.0 : (rescued.to_f / prows.size).round(3),
          mean_gap:   gaps.empty? ? nil : (gaps.sum / gaps.size).round(2),
          median_gap: gaps.empty? ? nil : median(gaps.sort).round(2),
          categories: prows.filter_map(&:fix_category).tally,
          sizes:      prows.filter_map(&:changed_chars),
          compliance: compliance,
          tokens_in:  prows.sum { |r| r.token_count_in.to_i },
          tokens_out: prows.sum { |r| r.token_count_out.to_i },
          cost:       prows.sum { |r| r.cost.to_f }.round(4)
        }
      end
      result[label] = per_problem
    end
    result
  end

  # True median of a pre-sorted array: middle element for odd N, mean of
  # the two middle elements for even N (not the upper-middle element).
  # Used for median_gap here and for median_size in the near_miss:report
  # rake task, so both agree on the same definition.
  def self.median(sorted_array)
    return nil if sorted_array.empty?
    mid = sorted_array.size / 2
    if sorted_array.size.odd?
      sorted_array[mid]
    else
      (sorted_array[mid - 1] + sorted_array[mid]) / 2.0
    end
  end
end
