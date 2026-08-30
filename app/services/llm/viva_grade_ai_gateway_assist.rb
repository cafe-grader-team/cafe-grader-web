module Llm
  # Hosted-gateway concrete subclass for viva grading. Transcript/rubric
  # handling lives in Llm::VivaGradeAssist; transport, default-model
  # resolution (default_models.viva_grade), and cost come from the mixin.
  class VivaGradeAiGatewayAssist < VivaGradeAssist
    include AiGatewayTransport

    GATEWAY_ROLE = :viva_grade

    # Drives the admin "Re-run grading" model picker on /submissions/:id/viva
    # (viva_sessions/show reads grader_class::KNOWN_MODELS). Snapshot of the
    # configured roster at class load; an out-of-list value typed by an admin
    # still reaches the gateway, which rejects unknown models with a 4xx.
    KNOWN_MODELS = Array(Rails.configuration.llm.dig(:ai_gateway, :models)).map(&:to_s).freeze
  end
end
