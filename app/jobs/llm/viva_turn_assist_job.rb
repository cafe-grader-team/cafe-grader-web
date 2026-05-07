module Llm
  class VivaTurnAssistJob < RequestJob
    private

    # The concrete viva turn service class is configured in config/llm.yml via
    #   viva_turn_service: Llm::VivaTurnGenieAssist
    # so deployment branches can plug in their provider without editing this file.
    # When unset, falls back to the abstract Llm::VivaTurnAssist, which raises
    # NotImplementedError at #execute_call (intentional on master).
    def service_class
      (Rails.configuration.llm[:viva_turn_service].presence || 'Llm::VivaTurnAssist').constantize
    end
  end
end
