class Job < ApplicationRecord
  enum :status, {wait: 0, process: 1, success: 2, error: 3}
  enum :job_type, {preprocess: 0, compile: 1, evaluate: 2, score: 3}, prefix: :jt

  scope :oldest_waiting, -> { where(status: :wait) }
  scope :finished, -> { where(status: [:success, :error]) }


  belongs_to :grader_process, optional: true

  # result should be EngineResponse::Result
  def report(result)
    update(status: result.status, result: result.result_description)
  end

  def to_text
    "Job #{id} type: #{job_type}, arg: #{arg}"
  end

  #
  # ---- class method
  #

  def self.add_grade_submission_job(submission, dataset, priority)
    # just add normal compile job
    self.add_compiling_job(submission, dataset, priority)
  end

  def self.add_compiling_job(submission, dataset, priority)
    raise GraderError.new("Sub ##{submission.id} does not have live dataset",
                          submission_id: submission.id) unless dataset
    Job.create(parent_job_id: nil,
               job_type: :compile,
               arg: submission.id,
               priority: priority,
               param: {dataset_id: dataset.id}.to_json)
  end

  def self.add_evaluation_jobs(submission, dataset, parent_job_id = nil, priority = 0)
    raise GraderError.new("Sub ##{submission.id} cannot find dataset #{dataset.id}",
                          submission_id: submission.id) unless dataset
    dataset.testcases.each do |testcase|
      Job.create(parent_job_id: parent_job_id,
                 job_type: :evaluate,
                 arg: submission.id,
                 priority: priority,
                 param: {testcase_id: testcase.id}.to_json)
    end
  end

  def self.add_scoring_job(submission, dataset, parent_job_id = nil, priority = 0)
    Job.create(parent_job_id: parent_job_id,
               job_type: :score,
               arg: submission.id,
               priority: priority,
               param: {dataset_id: dataset.id}.to_json)
  end

  def self.has_waiting_job(job_type = nil)
    q = Job.where(status: :wait)
    q = q.where(job_type: job_type) unless job_type.nil?
    return q.exists?
  end

  # fetch jobs from the queue, only for given job_type, if given
  def self.take_oldest_waiting_job(grader_process, job_type = nil)
    job = nil
    Job.transaction do
      # pick non-locked oldest_waiting
      # https://dev.mysql.com/doc/refman/8.0/en/innodb-locking-reads.html#innodb-locking-reads-nowait-skip-locked
      jobs = Job.lock("FOR UPDATE SKIP LOCKED").oldest_waiting
      jobs = jobs.where(job_type: job_type) unless job_type.nil?
      job = jobs.order('priority DESC, id ASC').first

      if job
        job.update(status: :process, grader_process: grader_process)
      end
    end
    return job
  end

  # check if all evaluation with the same parent of *job* are all finish
  def self.all_evaluate_job_complete(job)
    Job.where(parent_job_id: job.parent_job_id, job_type: :evaluate).where.not(status: :success).count == 0
  end

  # delete successful jobs older than x (errors are kept until admin clears them)
  # Nightly trim, run by Grader.cleanup_web. Finished-OK rows are pure history
  # once the submission carries its grade, so they go after a day. Error rows
  # are the debugging trail for reclaim sweeps and outages (the Graders page
  # lists the latest 50 with Retry All / Clear All), so they stay longer — but
  # not forever: on 2026-09-08 comprog still carried 4,422 dead rows from the
  # 2026-08-30 outage and every judge poll scanned them. Returns the number of
  # rows removed.
  def self.clean_old_job(x = 1.day, error_after: 30.days)
    now = Time.zone.now
    Job.where(status: :success).where('updated_at < ?', now - x).delete_all +
      Job.where(status: :error).where('updated_at < ?', now - error_after).delete_all
  end

  #
  # ---- chains ----
  #

  # Submission#add_judge_job starts a chain: one compile job, then the
  # evaluate jobs and the score job it leads to, which carry the compile
  # job's id as parent_job_id. A rejudge starts a new chain with a higher id
  # while the old chain's rows stay in the table (errors for 30 days), so a
  # submission's current chain is the newest chain id among its rows.
  def chain_id
    jt_compile? ? id : parent_job_id
  end

  # chain_id in SQL, built as an Arel node rather than an interpolated string
  def self.chain_id_expression
    Arel::Nodes::Case.new(arel_table[:job_type])
      .when(job_types[:compile]).then(arel_table[:id])
      .else(arel_table[:parent_job_id])
  end

  # {submission_id => newest chain id among its job rows}. Counts a chain's
  # evaluate and score rows, not only its compile row: clean_old_job deletes
  # a successful compile row after a day but keeps the chain's error rows
  # for 30.
  def self.newest_chain_ids(submission_ids)
    where(arg: submission_ids).group(:arg).maximum(chain_id_expression)
  end

  # False once a rejudge has started a newer chain for the submission. The
  # grader asks after it claims a job and again before each write the job
  # makes (compiled binary and status, evaluation row, score, grading
  # error), so a chain overtaken mid-run stops instead of writing over the
  # new one. A row with no chain id (none are created today) counts as
  # current, as every row did before chains were checked.
  def self.chain_current?(submission_id, chain_id)
    return true if chain_id.nil?
    newest = newest_chain_ids([submission_id])[submission_id]
    newest.nil? || chain_id >= newest
  end

  SUPERSEDED_RESULT = 'superseded by rejudge'.freeze

  # Called first by Submission#add_judge_job: the submission's waiting and
  # processing jobs become errors, so a waiting one is never claimed and a
  # processing one stops at its next chain check. Returns the row count.
  def self.supersede!(submission)
    where(arg: submission.id, status: [:wait, :process])
      .update_all(status: :error, result: SUPERSEDED_RESULT, updated_at: Time.zone.now)
  end

  def superseded!
    update(status: :error, result: SUPERSEDED_RESULT)
  end

  # A submission in one of these has finished its newest grading, so an error
  # row it still has is history — also once the newer chain's own rows have
  # been cleaned away and the row looks current again.
  RETRY_SETTLED_STATUSES = %w[done compilation_error].freeze

  # Split error jobs into [retryable, skipped] for Retry and Retry All on the
  # Graders page. Retryable: the submission still exists, is not settled,
  # and no newer chain has rows for it. Retry All used to requeue every error
  # row, so a row left behind by a rejudge ran again beside the new chain and
  # both wrote the submission's evaluations.
  def self.split_retryable(jobs)
    sub_ids = jobs.map(&:arg).compact.uniq
    open_ids = Submission.where(id: sub_ids).where.not(status: RETRY_SETTLED_STATUSES).pluck(:id).to_set
    newest = newest_chain_ids(sub_ids)
    jobs.partition do |job|
      open_ids.include?(job.arg) && job.chain_id.present? && job.chain_id >= newest[job.arg]
    end
  end

  #
  # ---- reclaiming orphaned jobs ----
  #

  # How long a job may sit in :process before requeueing it stops being the
  # helpful thing to do. Well above the longest legitimate single job — a
  # compile is capped at 10s (Compiler#compile) and the largest dataset
  # time_limit in production is 5s — so this is not a race window, it is the
  # point past which regrading has become a surprise rather than a repair.
  MAX_RECLAIM_AGE = 24.hours

  # Shared budget with check_and_run_job's rescue, which parses the same
  # "retry N" prefix out of #result: a job that keeps taking its grader down
  # with it must not requeue forever. Attempts 1..N-1 requeue, attempt N is
  # dead-lettered — same arithmetic as the rescue there.
  RECLAIM_ATTEMPT_LIMIT = 3

  # Return jobs whose grader claimed them and never reported back to the
  # queue. A job reaches :process in take_oldest_waiting_job and leaves it
  # only through Job#report; if the grader dies in between — OOM, kill -9, a
  # host reboot, the watchdog's stalled-KILL branch (Grader.plan_box) —
  # nothing ever flips it back. Its parent chain never completes and its
  # submission sits in :evaluating forever.
  #
  # Requeueing is safe in principle: compile, evaluate and score are all
  # re-runnable, Evaluation is find_or_create_by per (submission, testcase),
  # and Evaluator#prepare_executable re-downloads the compiled binary rather
  # than trusting whatever the judge box still has on disk. It is only
  # *meaningful*, though, while the submission is still mid-flight, so two
  # cases are dead-lettered to :error rather than requeued:
  #
  #   * the submission already reached a GRADING_FINAL_STATUS — an admin
  #     rejudged it, or a sibling chain finished it. Re-running would
  #     overwrite a settled grade, and Grader.cleanup_web has since purged
  #     the compiled binary an evaluate job would need anyway.
  #   * the job has been stuck longer than MAX_RECLAIM_AGE.
  #
  # A submission still mid-flight is marked grader_error, so it stops showing
  # "evaluating" and the ordinary admin Rejudge path applies to it.
  #
  # Two callers, deliberately different in how each proves the grader is gone:
  #   * Grader.watchdog passes grader_process_ids: for the boxes its own `ps`
  #     sweep just proved have no process running at all. No timing heuristic,
  #     so it cannot yank a job out from under a grader that is merely slow;
  #     latency is one watchdog tick. The default older_than: still applies,
  #     closing the sub-second gap between that ps snapshot and this query in
  #     which a starting grader could claim a fresh job.
  #   * a Solid Queue recurring task passes a generous older_than: as a
  #     fleet-wide backstop, for a host whose watchdog is itself not running
  #     (that is exactly when the ps-based path cannot fire).
  #
  # Returns {requeued:, abandoned:}.
  def self.reclaim_orphaned!(grader_process_ids: nil, older_than: 1.minute)
    scope = Job.where(status: :process).where('updated_at < ?', Time.zone.now - older_than)
    scope = scope.where(grader_process_id: grader_process_ids) if grader_process_ids
    stats = {requeued: 0, abandoned: 0}

    scope.includes(:grader_process).find_each do |job|
      sub = Submission.find_by(id: job.arg)
      mid_flight = sub && !Submission::GRADING_FINAL_STATUSES.include?(sub.status)
      attempt = (job.result&.match(/retry (\d+)/)&.[](1)&.to_i || 0) + 1
      reason =
        if sub.nil?
          'submission no longer exists'
        elsif !mid_flight
          "submission already #{sub.status}"
        elsif job.updated_at < Time.zone.now - MAX_RECLAIM_AGE
          "stuck since #{job.updated_at.to_fs(:db)}"
        elsif attempt >= RECLAIM_ATTEMPT_LIMIT
          "grader died on it #{attempt} times"
        end

      if reason
        job.update(status: :error, result: "reclaim gave up (#{job.grader_label}): #{reason}".truncate(255))
        sub.set_grading_error('Grading was interrupted and could not be resumed. Please rejudge.') if mid_flight
        stats[:abandoned] += 1
      else
        job.update(status: :wait, result: "retry #{attempt}: reclaimed, #{job.grader_label} died mid-job".truncate(255))
        stats[:requeued] += 1
      end
    end

    if stats.values.sum > 0
      Rails.logger.warn("[Job.reclaim_orphaned!] requeued #{stats[:requeued]}, abandoned #{stats[:abandoned]}")
    end
    stats
  end

  # Which grader claimed this job, for the reclaim message. The row survives
  # the process (find_or_create_by per worker/box in Grader#initialize), so
  # this names the box, not the dead pid.
  def grader_label
    gp = grader_process
    return 'no grader' unless gp
    "grader worker #{gp.worker_id} box #{gp.box_id}"
  end
end
