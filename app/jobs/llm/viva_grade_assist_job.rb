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

    # Mark the submission as :grader_error after retries are exhausted.
    # Grade flow has no separate placeholder turn — the submission itself
    # carries the failure state via status + grader_comment.
    def on_retries_exhausted(error)
      return unless @submission
      @submission.update(status: :grader_error,
                         grader_comment: "Grader error (retries exhausted): #{error.class.name}: #{error.message}")
    rescue => e
      Rails.logger.error "on_retries_exhausted failed for VivaGradeAssistJob: #{e.class}: #{e.message}"
    end
  end
end
