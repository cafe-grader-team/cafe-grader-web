module Llm
  # Hosted-gateway concrete subclass for comment-on-submission. Register
  # served models in llm.yml's per-model map (AiGatewayAssist: model-a,model-b)
  # to expose them in the assist picker beside other providers; anything
  # outside the configured roster is clamped back to the role default —
  # GenieAssist's PERMITTED_MODEL guard with config as the source of truth.
  class AiGatewayAssist < CommentAssist
    include AiGatewayTransport

    GATEWAY_ROLE = :assist

    private

    def prepare_data
      @model = gateway_default_model unless self.class.gateway_models.include?(@model.to_s)
      super
    end
  end
end
