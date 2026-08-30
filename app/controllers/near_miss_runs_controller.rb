# Instructor-facing browser for Near-Miss repair runs (read-only — the data
# is produced by `rake near_miss:repair`). Three levels: run list ->
# per-run/per-problem report (SubmissionRepair.report_for) -> attempt detail.
# Spec: docs/superpowers/specs/2026-07-30-near-miss-grading-design.md §9.2/§13.
class NearMissRunsController < ApplicationController
  before_action :admin_authorization

  def index
    agg = SubmissionRepair.joins(:original_submission).group(:run_label).pluck(
      :run_label,
      Arel.sql('COUNT(*)'),
      Arel.sql('COUNT(DISTINCT submissions.problem_id)'),
      Arel.sql('MIN(submission_repairs.created_at)'),
      Arel.sql('MAX(submission_repairs.updated_at)'),
      Arel.sql('SUM(COALESCE(submission_repairs.token_count_in, 0))'),
      Arel.sql('SUM(COALESCE(submission_repairs.token_count_out, 0))'),
      Arel.sql('SUM(COALESCE(submission_repairs.cost, 0))'),
      Arel.sql("GROUP_CONCAT(DISTINCT submission_repairs.llm_model ORDER BY submission_repairs.llm_model SEPARATOR ', ')"),
      Arel.sql("GROUP_CONCAT(DISTINCT CONCAT(submission_repairs.budget_lines, 'L / ', submission_repairs.budget_chars, 'C') SEPARATOR ', ')"))
    statuses = SubmissionRepair.group(:run_label, :status).count
    rescued  = rescued_counts
    @runs = agg.map do |label, attempts, problems, first_at, last_at, tin, tout, cost, models, budgets|
      {label: label, attempts: attempts, problems: problems,
       first_at: first_at, last_at: last_at,
       tokens_in: tin.to_i, tokens_out: tout.to_i, cost: cost.to_f,
       models: models, budgets: budgets,
       statuses: statuses.filter_map { |(l, s), n| [s, n] if l == label }.to_h,
       rescued: rescued[label].to_i}
    end.sort_by { |r| r[:last_at] }.reverse
  end

  def show
    @labels = requested_labels
    return redirect_to near_miss_runs_path if @labels.empty?

    @report = SubmissionRepair.report_for(@labels)
    scope = SubmissionRepair.where(run_label: @labels)
    @status_counts = scope.group(:status).count
    @status_filter = params[:status].presence_in(SubmissionRepair.statuses.keys)
    scope = scope.where(status: @status_filter) if @status_filter
    @attempts = scope.includes(original_submission: [:user, :problem], repaired_submission: [])
                     .order(:run_label, :id)
  end

  def repair
    @repair = SubmissionRepair.includes(original_submission: [:user, :problem],
                                        repaired_submission: []).find(params[:id])
    @original = @repair.original_submission
    @shadow   = @repair.repaired_submission
  end

  private

  # ?runs= accepts both the comma-joined form (links; same syntax as the rake
  # RUN= parameter) and the checkbox-array form from the compare form.
  def requested_labels
    Array(params[:runs]).flat_map { |v| v.to_s.split(',') }
                        .map(&:strip).reject(&:empty?).uniq
  end

  # {run_label => accepted attempts whose shadow outscored the original} —
  # same "rescued" definition as SubmissionRepair.report_for.
  def rescued_counts
    SubmissionRepair.accepted
      .joins('INNER JOIN submissions orig ON orig.id = submission_repairs.original_submission_id')
      .joins('INNER JOIN submissions rep  ON rep.id  = submission_repairs.repaired_submission_id')
      .where('rep.points > orig.points')
      .group(:run_label).count
  end
end
