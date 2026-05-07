module Llm
  # Comment-on-submission shape: the LLM call writes its outcome to a Comment
  # record (cost / llm_response / status / parse_response result, or an error
  # block on failure). Provider-specific subclasses (e.g. GenieAssist on the
  # chula_cp branch) supply prepare_data / execute_call / parse_response /
  # validate_response_body! / provider_name.
  class CommentAssist < Request
    def initialize(submission:, comment:, **args)
      super(submission: submission, **args)
      @record = comment
      raise ArgumentError, "Comment object is required" unless @record
    end

    private

    def parse_response
      raise NotImplementedError, "#{self.class} must implement #parse_response"
    end

    def validate_response_body!
      raise NotImplementedError, "#{self.class} must implement #validate_response_body!"
    end

    def handle_response(response)
      # Faraday's f.response :raise_error means non-2xx already raised before
      # we got here, so we don't re-check response.success?.
      @parsed_body = JSON.parse(response.body)
      validate_response_body!

      @record.cost = 10
      @record.llm_response = response.body
      @record.status = 'ok'
      @record.update!(parse_response)
    rescue JSON::ParserError => e
      raise ResponseError.new("Invalid JSON from #{provider_name}: #{e.message}", body: response&.body)
    end

    def handle_error
      @record.title = "Assistant Error"
      @record.body += "* Request finished at `#{Time.zone.now}`\n"
      @record.body += "<div class='alert alert-danger'> <h5>Request failed</h5> #{@error} </div>"
      @record.status = 'error'
      @record.save!
    end

    def get_prompts_from_problem_tags
      @submission.problem.tags.where(kind: 'llm_prompt').map { |tag| tag.params }
    end
  end
end
