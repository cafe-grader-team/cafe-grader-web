# Drives one existing submission through the real grading chain on this host —
# compile, evaluate every testcase of the live dataset, score — exactly as
# Grader#process_job_compile / _evaluate / _scoring do, but synchronously and
# with no Job or GraderProcess row, so the watchdog never learns of the box and
# no grader can pick the work up. Entry point for `bin/rails engine:smoke`
# (lib/tasks/engine.rake): prove the engine works on a box before, or right
# after, a deploy. The 2026-08-30 outage was a run→check ordering bug that no
# test without isolate can see and that this shows in seconds.
#
# It regrades a real submission, so it snapshots the row's grade fields, its
# language and every Evaluation row first and puts them back in an ensure,
# whatever the chain did or raised. Like a real regrade it grades from no
# Evaluation rows. Use a box id no grader owns (99 by default).
class EngineSmoke
  GRADE_FIELDS = %w[status points grader_comment graded_at max_runtime peak_memory compiler_message].freeze
  # Restored as well as the grade: the chain's own validating save runs
  # Submission#assign_language, which relabels a submission on a problem that
  # now accepts a single language (comprog-grader, 2026-09-25: three C++
  # submissions were left labelled Python).
  RESTORED_FIELDS = (GRADE_FIELDS + %w[language_id]).freeze

  Report = Struct.new(:submission_id, :dataset_id, :before, :after, :evaluations, :error, keyword_init: true)

  def initialize(submission, box_id: 99, worker_id: Rails.configuration.worker[:worker_id],
                 compiler: Compiler, evaluator: Evaluator, scorer: Scorer)
    @sub = submission
    @box_id = box_id
    @worker_id = worker_id
    @compiler = compiler
    @evaluator = evaluator
    @scorer = scorer
  end

  def run
    dataset = @sub.problem.live_dataset
    raise ArgumentError, "submission #{@sub.id} has no live dataset" unless dataset

    before = grade_snapshot
    saved = @sub.slice(*RESTORED_FIELDS)
    evaluation_rows = Evaluation.where(submission: @sub).map(&:attributes)
    report = Report.new(submission_id: @sub.id, dataset_id: dataset.id,
                        before: before.symbolize_keys, evaluations: [])
    begin
      # A real regrade starts from no rows (Submission#add_judge_job). The
      # evaluator updates the row it finds and its crash path leaves the score
      # alone, so grading on top of the stored rows let a crashed testcase keep
      # its stored score (2026-09-25 log: "crash score=1.0", points 100).
      Evaluation.where(submission: @sub).delete_all
      @compiler.get_compiler(@sub).new(@worker_id, @box_id).compile(@sub, dataset)
      @sub.reload
      if @sub.compilation_success?
        dataset.testcases.each do |tc|
          @evaluator.get_evaluator(@sub).new(@worker_id, @box_id).execute(@sub, tc)
        end
        @scorer.get_scorer(@sub).new(@worker_id, @box_id).process(@sub, dataset)
        report.evaluations = dataset.testcases.filter_map do |tc|
          e = Evaluation.find_by(submission: @sub, testcase: tc)
          e && {testcase_id: tc.id, result: e.result, score: e.score, time: e.time, memory: e.memory, result_text: e.result_text}
        end
      end
    rescue => e
      report.error = e
    ensure
      report.after = grade_snapshot.symbolize_keys
      restore!(saved, evaluation_rows)
    end
    report
  end

  private

  def grade_snapshot
    @sub.reload.slice(*GRADE_FIELDS)
  end

  def restore!(fields, evaluation_rows)
    Submission.transaction do
      @sub.update_columns(fields)
      Evaluation.where(submission: @sub).delete_all
      Evaluation.insert_all(evaluation_rows) if evaluation_rows.any?
    end
  end
end
