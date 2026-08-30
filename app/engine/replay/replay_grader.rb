module Replay
  # Grades a single submission synchronously through the REAL judge pipeline
  # (compile -> evaluate -> score) on a dedicated isolate box. Dev/validation
  # diagnostic only; no background worker needed.
  #
  # Deviation from the original spike sketch: this does NOT drain the global
  # job queue via Grader#check_and_run_job / Job.take_oldest_waiting_job.
  # Those pull the oldest *waiting job of any submission* -- on this dev box
  # there is real queue debris (jobs stuck in `wait`/`process` from earlier,
  # unrelated grading activity) that must never be touched by a validation
  # harness. Instead we drain only *this submission's own* jobs (`arg ==
  # submission.id`), while still calling the real Grader#process_job_* engine
  # methods (real Compiler/Evaluator/Scorer on a real isolate box) so the
  # result is a genuine grade, not a simulation.
  module ReplayGrader
    module_function

    REPLAY_BOX_ID = (ENV['REPLAY_BOX_ID'] || 90).to_i        # avoid clashing with real workers' boxes
    # grader_processes.worker_id / worker_datasets.worker_id are integer columns;
    # keep this numeric (rather than the sketch's 'replay' string) so it doesn't
    # silently coerce to 0 and collide with a real worker_id.
    REPLAY_WORKER_ID = (ENV['REPLAY_WORKER_ID'] || 99).to_i

    TERMINAL_STATUSES = %w[done compilation_error grader_error].freeze

    # Grades +submission+ against +dataset+ synchronously and returns the
    # terminal result:
    #   { points: Float|nil, grader_comment: String|nil, status: String }
    def grade_sync(submission, dataset, deadline: 600)
      Job.where(arg: submission.id).delete_all   # clear any stale jobs for this submission before a fresh grade
      submission.add_judge_job(dataset) # enqueues the compile job (resets status)
      grader = Grader.new(REPLAY_WORKER_ID, REPLAY_BOX_ID)

      started = Time.zone.now
      loop do
        job = take_next_job(submission)
        break if job.nil?

        run_job(grader, job)

        submission.reload
        break if terminal?(submission.status)

        if (Time.zone.now - started) > deadline
          raise "replay grading exceeded #{deadline}s for sub ##{submission.id}"
        end
      end

      { points: submission.points, grader_comment: submission.grader_comment, status: submission.status.to_s }
    end

    def terminal?(status)
      TERMINAL_STATUSES.include?(status.to_s)
    end

    # Locks and claims the oldest waiting job that belongs to THIS submission
    # only (mirrors Job.take_oldest_waiting_job, but scoped by arg so unrelated
    # queued jobs on a shared dev DB are never picked up).
    def take_next_job(submission)
      job = nil
      Job.transaction do
        jobs = Job.lock('FOR UPDATE SKIP LOCKED').where(status: :wait, arg: submission.id)
        job = jobs.order('priority DESC, id ASC').first
        job.update(status: :process) if job
      end
      job
    end
    private_class_method :take_next_job

    # Runs one job through the real Grader engine methods, replicating the
    # relevant part of Grader#check_and_run_job's error handling (GraderError
    # -> grader_error on the submission). Unlike the production main loop,
    # an unexpected StandardError is NOT swallowed/retried here -- this is a
    # one-shot synchronous call, so a genuine engine bug should raise and
    # fail the spike loudly rather than be masked behind a "retry 3 times
    # then give up" daemon behavior meant for a long-running worker.
    def run_job(grader, job)
      grader.job = job
      case job.job_type
      when 'compile'  then grader.process_job_compile
      when 'evaluate' then grader.process_job_evaluate
      when 'score'    then grader.process_job_scoring
      else
        job.update(status: :error, result: 'replay grader has no handler for this job_type')
      end
    rescue GraderError, ActiveRecord::RecordNotFound => ge
      job.update(status: :error, result: ge.message) if ge.end_job
      if ge.update_submission
        s = Submission.find(ge.submission_id)
        s.set_grading_error(ge.message_for_user)
      end
    ensure
      grader.job = nil
    end
    private_class_method :run_job
  end
end
