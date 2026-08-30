module Llm
  # GroundingMaterial has no Submission, so this does NOT reuse RequestJob's
  # base #perform(submission, **job_args) — that hardcodes `submission` as
  # the first positional arg and threads it through as submission: to
  # service_class.call, which doesn't apply here. #perform is overridden
  # below with the equivalent shape for grounding_material:, mirroring
  # RequestJob's retry/rescue structure exactly (retry_on / RETRY_EXHAUSTED
  # are registered at the RequestJob class level and still apply regardless
  # of which perform method raises).
  class GroundingExtractJob < RequestJob
    # The concrete extraction service class is configured in config/llm.yml via
    #   grounding_extract_service: Llm::GroundingExtractGenieAssist
    # so deployment branches can plug in their provider without editing this file.
    # When unset, falls back to the abstract Llm::GroundingExtractAssist, which
    # raises NotImplementedError at #execute_call (intentional on master).
    def perform(grounding_material, **job_args)
      @grounding_material = grounding_material
      @job_args = job_args
      Rails.logger.info "Starting #{service_class.name} for GroundingMaterial ##{grounding_material.id}"
      service_class.call(grounding_material: grounding_material, **job_args)
    rescue *RETRYABLE_ERRORS
      raise
    rescue => e
      Rails.logger.error "Service #{service_class.name} failed (non-retryable): #{e.class}: #{e.message}"
      on_retries_exhausted(e)
      raise
    end

    private

    def service_class
      (Rails.configuration.llm[:grounding_extract_service].presence || 'Llm::GroundingExtractAssist').constantize
    end

    # Mark the placeholder draft as :error (via the "EXTRACTION FAILED:"
    # prefix convention, same one Llm::GroundingExtractAssist#handle_error
    # uses) after retries are exhausted, so the edit view stops showing
    # "Extraction in progress…" forever.
    def on_retries_exhausted(error)
      gm = @grounding_material
      return unless gm
      gm.update(extraction_draft: "EXTRACTION FAILED (retries exhausted): #{error.class.name}: #{error.message}")
    rescue => e
      Rails.logger.error "on_retries_exhausted failed for GroundingExtractJob: #{e.class}: #{e.message}"
    end
  end
end
