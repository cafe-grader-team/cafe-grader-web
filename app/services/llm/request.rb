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

    # Build the LLM payload (the body that #execute_call would POST) WITHOUT
    # making the network call or touching any DB record. Useful from the
    # Rails console to debug prompt assembly:
    #
    #   sub  = Submission.find(922236)
    #   turn = sub.viva_turns.last
    #   pp Llm::VivaTurnGenieAssist.preview(submission: sub, turn: turn)
    #
    # Returns a hash with symbol keys regardless of whether prepare_data
    # yields a hash (viva subclasses) or a JSON-encoded string (CommentAssist
    # family), so it's always inspectable via `pp` / `JSON.pretty_generate`.
    #
    # Long base64 attachments (PDFs encoded as image_url) are redacted to a
    # short "<MIME base64, ~XKB redacted>" placeholder by default — pass
    # `redact: false` to see the literal data URI.
    def self.preview(redact: true, **args)
      data = new(**args).send(:prepare_data)
      data = JSON.parse(data, symbolize_names: true) if data.is_a?(String)
      redact ? redact_long_attachments(data) : data
    end

    # Walk a payload's messages array and replace long base64-encoded
    # data: URIs in image_url content parts with a short placeholder.
    # Keys are assumed to be symbols (preview normalizes to symbol keys
    # via symbolize_names: true on JSON.parse).
    def self.redact_long_attachments(data)
      return data unless data.is_a?(Hash) && data[:messages].is_a?(Array)
      data[:messages].each do |msg|
        next unless msg[:content].is_a?(Array)
        msg[:content].each do |part|
          next unless part.is_a?(Hash) && part[:type] == "image_url"
          url = part[:image_url]
          next unless url.is_a?(String) && url.length > 500 && url.start_with?("data:")
          mime = url[/\Adata:([^;]+);/, 1] || "binary"
          kb   = (url.length / 1024.0).round
          part[:image_url] = "<#{mime} base64, ~#{kb}KB redacted>"
        end
      end
      data
    end
    private_class_method :redact_long_attachments

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

    # Base64-encode the problem statement PDF as an image_url content part
    # in the OpenAI-compatible multimodal shape. Returns nil when no PDF is
    # attached or the attached file isn't application/pdf — callers should
    # treat that as "no PDF for this problem" and fall back to text only.
    # Used by both CommentAssist and the viva subclasses.
    def pdf_attachment
      return nil unless problem&.statement&.attached?
      return nil unless problem.statement.content_type == 'application/pdf'

      pdf_binary  = problem.statement.download
      encoded_pdf = Base64.strict_encode64(pdf_binary)

      {
        type:      "image_url",  # API spec uses 'image_url' for this content type
        image_url: "data:application/pdf;base64,#{encoded_pdf}"
      }
    rescue => e
      msg = "Failed to build PDF attachment for Problem ##{problem.id}: #{e.message}"
      Rails.logger.error msg
      raise RuntimeError, msg
    end

    # Collapse consecutive messages of the same role into one (contents joined
    # with a blank line). OpenAI-compatible chat-completion endpoints generally
    # expect alternating user/assistant turns after the system message; some
    # downstream models (notably Anthropic Claude) reject consecutive same-role
    # messages outright. Subclasses that build a string-content messages array
    # (the viva subclasses) should call this before returning. Messages whose
    # content isn't a String (e.g., the multimodal content arrays used by
    # CommentAssist) are left untouched — joining those with "\n\n" would
    # corrupt the wire shape.
    def consolidate_role_runs(messages)
      messages.chunk_while do |a, b|
        a[:role] == b[:role] && a[:content].is_a?(String) && b[:content].is_a?(String)
      end.map do |group|
        next group.first if group.size == 1
        {role: group.first[:role], content: group.map { |m| m[:content] }.join("\n\n")}
      end
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
