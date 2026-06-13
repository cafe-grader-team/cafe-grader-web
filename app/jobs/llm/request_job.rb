module Llm
  # Abstract base for any LLM-call job. Subclasses only need to declare
  # which service class to instantiate via #service_class.
  #
  # When a RETRYABLE exception (network timeout etc.) is hit, retry_on
  # silently retries up to N times without marking the placeholder record
  # as :error — so that a successful retry doesn't have to flip the
  # record back to :ok and cause a UI flicker. The downside: if every
  # retry fails, the placeholder stays in :processing forever, and the
  # user sees an eternal "Interviewer is thinking…" spinner with no
  # signal. To close that gap, each retry_on uses the BLOCK form: when
  # retries are exhausted, RETRY_EXHAUSTED runs job.on_retries_exhausted
  # which lets the concrete subclass mark its placeholder record as
  # :error before the exception propagates to Solid Queue.
  class RequestJob < ApplicationJob
    # Errors that retry_on covers. Listed once so the rescue clause in
    # #perform can let them through to retry_on instead of treating them
    # as terminal failures.
    RETRYABLE_ERRORS = [
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      ActiveRecord::Deadlocked,
      ActiveRecord::ConnectionTimeoutError
    ].freeze

    RETRY_EXHAUSTED = ->(job, error) do
      job.send(:on_retries_exhausted, error)
      raise error
    end

    retry_on Faraday::TimeoutError,                wait: :polynomially_longer, attempts: 3, &RETRY_EXHAUSTED
    retry_on Faraday::ConnectionFailed,            wait: 5.seconds,  attempts: 3, &RETRY_EXHAUSTED
    retry_on ActiveRecord::Deadlocked,             wait: 5.seconds,  attempts: 3, &RETRY_EXHAUSTED
    retry_on ActiveRecord::ConnectionTimeoutError, wait: 10.seconds, attempts: 3, &RETRY_EXHAUSTED

    # Placeholder record was deleted between enqueue and run — nothing to mark.
    discard_on ActiveJob::DeserializationError

    # Convention: every concrete LLM job is enqueued with the submission as
    # the first positional argument plus per-service kwargs (e.g., turn:,
    # comment:, model:). The service classes accept submission as a kwarg, so
    # we re-thread it. Don't change to `*args, **kwargs` pass-through —
    # Llm::Request.call is kwargs-only and the positional would crash with
    # "wrong number of arguments (given 1, expected 0)".
    def perform(submission, **job_args)
      # Stash on the instance so on_retries_exhausted (called from the
      # class-level lambda) can access them.
      @submission = submission
      @job_args   = job_args
      Rails.logger.info "Starting #{service_class.name} for Submission ##{submission.id}"
      service_class.call(submission: submission, **job_args)
    rescue *RETRYABLE_ERRORS
      # retry_on handles these externally; pass through unchanged so the
      # next attempt (or RETRY_EXHAUSTED) runs.
      raise
    rescue => e
      # Non-retryable failure (NotImplementedError, JSON parse errors,
      # provider 4xx/5xx surfaced as something other than a Faraday
      # error, etc.). Without this branch, the placeholder record stays
      # in :processing forever — the user sees an eternal
      # "Interviewer is thinking..." spinner. Reuse on_retries_exhausted
      # so the failure shape matches the retry-exhausted path.
      Rails.logger.error "Service #{service_class.name} failed (non-retryable): #{e.class}: #{e.message}"
      on_retries_exhausted(e)
      raise
    end

    private

    # Called by RETRY_EXHAUSTED once retry_on has run out of attempts.
    # Concrete subclasses override to mark their placeholder record so
    # the user sees a final failure instead of a frozen spinner. The
    # default is a no-op so subclasses without a placeholder still work.
    def on_retries_exhausted(error)
      # default no-op; subclasses override
    end

    def service_class
      raise NotImplementedError, "#{self.class} must implement #service_class"
    end
  end
end
