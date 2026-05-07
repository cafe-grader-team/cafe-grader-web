module Llm
  # Abstract base for any LLM-call job. Subclasses only need to declare
  # which service class to instantiate via #service_class.
  class RequestJob < ApplicationJob
    retry_on Faraday::TimeoutError,                wait: :polynomially_longer, attempts: 3
    retry_on Faraday::ConnectionFailed,            wait: 5.seconds,  attempts: 3
    retry_on ActiveRecord::Deadlocked,             wait: 5.seconds,  attempts: 3
    retry_on ActiveRecord::ConnectionTimeoutError, wait: 10.seconds, attempts: 3

    # Placeholder record was deleted between enqueue and run — nothing to mark.
    discard_on ActiveJob::DeserializationError

    # Convention: every concrete LLM job is enqueued with the submission as
    # the first positional argument plus per-service kwargs (e.g., turn:,
    # comment:, model:). The service classes accept submission as a kwarg, so
    # we re-thread it. Don't change to `*args, **kwargs` pass-through —
    # Llm::Request.call is kwargs-only and the positional would crash with
    # "wrong number of arguments (given 1, expected 0)".
    def perform(submission, **job_args)
      Rails.logger.info "Starting #{service_class.name} for Submission ##{submission.id}"
      service_class.call(submission: submission, **job_args)
    rescue => e
      Rails.logger.error "Service #{service_class.name} failed: #{e.class}: #{e.message}"
      raise
    end

    private

    def service_class
      raise NotImplementedError, "#{self.class} must implement #service_class"
    end
  end
end
