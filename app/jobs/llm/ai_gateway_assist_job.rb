module Llm
  # Comment-style assist job for the hosted AI-gateway provider. Resolved by
  # comments_controller#llm_assist as provider-class-name + 'Job'.
  # on_retries_exhausted (mark the Comment :error) is inherited from
  # CommentAssistJob.
  class AiGatewayAssistJob < CommentAssistJob
    private

    def service_class
      Llm::AiGatewayAssist
    end
  end
end
