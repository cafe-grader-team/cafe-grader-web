module Llm
  # Abstract base for any single LLM HTTP call. Owns orchestration only:
  # the call-template flow, the Faraday connection factory, and the rescue
  # contract. Knows nothing about Comments, VivaTurns, VivaGrades, or any
  # other domain record. Concrete subclasses (CommentAssist, VivaTurnAssist,
  # VivaGradeAssist) implement record-specific handle_response / handle_error.
  class Request
    attr_reader :submission, :problem, :error

    # Exceptions whose semantics are "ask the worker to retry"; the service
    # re-raises these without touching the record so a successful retry
    # doesn't have to overwrite a brief :error flicker in the UI.
    RETRYABLE = [
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      ActiveRecord::Deadlocked,
      ActiveRecord::ConnectionTimeoutError
    ].freeze

    # Raised when the upstream returns a parsable HTTP success but the body
    # is not what we can use (bad JSON, wrong shape, missing fields). This
    # is deterministic, not transient — never retried.
    class ResponseError < StandardError
      attr_reader :status, :body
      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    # Convenience: SubclassName.call(submission: ..., **args)
    def self.call(**args)
      new(**args).call
    end

    def initialize(submission:, **args)
      @submission = submission
      @problem    = submission.problem
      @error      = nil
      @other_args = args
    end

    def call
      data = prepare_data
      response = execute_call(data)
      handle_response(response)
    rescue *RETRYABLE
      raise
    rescue StandardError, NotImplementedError => e
      @error = format_error(e)
      begin
        handle_error
      rescue => he
        Rails.logger.error("handle_error failed for #{self.class}: #{he.class}: #{he.message}")
      end
      raise
    end

    # Faraday factory used by all concrete subclasses' execute_call.
    def self.connection(api_base_url)
      Faraday.new(url: api_base_url) do |f|
        f.options.timeout      = 300
        f.options.open_timeout = 10
        f.options.read_timeout = 300
        f.request :json
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end

    private

    def format_error(exception)
      "#{exception.class.name}: #{exception.message}"
    end

    def prepare_data
      raise NotImplementedError, "#{self.class} must implement #prepare_data"
    end

    def execute_call(data)
      raise NotImplementedError, "#{self.class} must implement #execute_call"
    end

    def handle_response(response)
      raise NotImplementedError, "#{self.class} must implement #handle_response"
    end

    def handle_error
      raise NotImplementedError, "#{self.class} must implement #handle_error"
    end

    def provider_name
      raise NotImplementedError, "#{self.class} must implement #provider_name"
    end
  end
end
