module Llm
  # Hosted-gateway concrete subclass for grounding PDF->markdown extraction.
  # The extraction contract / draft handling live in
  # Llm::GroundingExtractAssist; transport and default-model resolution
  # (default_models.grounding_extract — pick a cheap multimodal model; drafts
  # are always author-reviewed) come from the mixin.
  class GroundingExtractAiGatewayAssist < GroundingExtractAssist
    include AiGatewayTransport

    GATEWAY_ROLE = :grounding_extract
  end
end
