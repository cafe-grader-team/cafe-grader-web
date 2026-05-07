module Llm
  class VivaGradeAssistJob < RequestJob
    private

    # The concrete viva grade service class is configured in config/llm.yml via
    #   viva_grade_service: Llm::VivaGradeGenieAssist
    # so deployment branches can plug in their provider without editing this file.
    # When unset, falls back to the abstract Llm::VivaGradeAssist, which raises
    # NotImplementedError at #execute_call (intentional on master).
    def service_class
      (Rails.configuration.llm[:viva_grade_service].presence || 'Llm::VivaGradeAssist').constantize
    end
  end
end
