module Llm
  # Hosted-gateway concrete repair provider. The engine hands #execute_chat a
  # bare messages array; wrap it in the OpenAI wire shape and reuse the
  # mixin's transport — which also rewrites the statement-PDF part into a
  # `file` block, so the engine's default include_statement_pdf? stays true.
  class SubmissionRepairAiGatewayAssist < SubmissionRepairAssist
    include AiGatewayTransport

    GATEWAY_ROLE = :submission_repair

    private

    # SERVICE=/model_key selects within the configured roster; anything else
    # (including a self-host key left over in a command line) falls back to
    # the role default rather than erroring — mirrors the Genie guard.
    def resolved_model
      @resolved_model ||= begin
        m = @other_args[:model_key].presence&.to_s
        self.class.gateway_models.include?(m) ? m : gateway_default_model
      end
    end

    def execute_chat(messages)
      execute_call({model: resolved_model, messages: messages, stream: false})
    end

    def model_name_for_record = resolved_model
  end
end
