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

    # Mark the placeholder turn as :error after retries are exhausted so the
    # student sees a clear failure instead of an eternal "Interviewer is
    # thinking..." spinner. Inherited base would no-op; this override is what
    # actually closes the gap for the viva-turn flow.
    def on_retries_exhausted(error)
      turn = @job_args&.fetch(:turn, nil)
      return unless turn
      turn.update(status: :error,
                  content: "LLM error (retries exhausted): #{error.class.name}: #{error.message}")
    rescue => e
      Rails.logger.error "on_retries_exhausted failed for VivaTurnAssistJob: #{e.class}: #{e.message}"
    end
  end
end
