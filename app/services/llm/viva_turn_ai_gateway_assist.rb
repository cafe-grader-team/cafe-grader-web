module Llm
  # Hosted-gateway concrete subclass for viva interview turns. Message and
  # response handling live in Llm::VivaTurnAssist; transport, default-model
  # resolution (default_models.viva_turn), and cost come from the mixin.
  class VivaTurnAiGatewayAssist < VivaTurnAssist
    include AiGatewayTransport

    GATEWAY_ROLE = :viva_turn
  end
end
