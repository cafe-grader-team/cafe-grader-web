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

    def perform(*args, **kwargs)
      Rails.logger.info "Starting #{service_class.name}"
      service_class.call(*args, **kwargs)
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
