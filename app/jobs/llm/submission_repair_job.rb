module Llm
  class SubmissionRepairJob < RequestJob
    private

    # Concrete repair service is configured in config/llm.yml via
    #   submission_repair_service: Llm::SubmissionRepairSelfHostAssist
    # (viva registration pattern). Blank on master -> the abstract base
    # raises NotImplementedError at execute_chat (intentional).
    def service_class
      (Rails.configuration.llm[:submission_repair_service].presence || 'Llm::SubmissionRepairAssist').constantize
    end

    def on_retries_exhausted(error)
      repair = @job_args&.fetch(:repair, nil)
      return unless repair
      repair.update(status: :failed,
                    remark: "LLM error (retries exhausted): #{error.class.name}: #{error.message}")
    rescue => e
      Rails.logger.error "on_retries_exhausted failed for SubmissionRepairJob: #{e.class}: #{e.message}"
    end
  end
end
