module Llm
  class VivaGradeAssistJob < RequestJob
    # Grading shares the `viva` queue with interview turns — see
    # VivaTurnAssistJob and config/queue.yml.
    queue_as :viva

    private

    # The concrete viva grade service class is configured in config/llm.yml via
    #   viva_grade_service: Llm::VivaGradeGenieAssist
    # so deployment branches can plug in their provider without editing this file.
    # When unset, falls back to the abstract Llm::VivaGradeAssist, which raises
    # NotImplementedError at #execute_call (intentional on master).
    def service_class
      (Rails.configuration.llm[:viva_grade_service].presence || 'Llm::VivaGradeAssist').constantize
    end

    # Runs after retry_on gives up (RETRY_EXHAUSTED) and from perform's rescue
    # of a non-retryable error. A retryable transport error never reaches the
    # service's handle_error, so the run's failure row is written here; a
    # non-retryable one was already recorded by
    # Llm::VivaGradeAssist#handle_error, so only the status is (re)checked.
    # The submission is marked grader_error only when it has no valid current
    # grade — a failed re-run never takes a grade away (grade history, spec
    # 2026-09-23).
    def on_retries_exhausted(error)
      return unless @submission
      if RETRYABLE_ERRORS.any? { |klass| error.is_a?(klass) }
        args = @job_args || {}
        VivaGrade.record_failure!(@submission, error: "#{error.class.name}: #{error.message}",
                                  model: args[:model], requested_by_id: args[:requested_by_id], batch_id: args[:batch_id],
                                  rubric_version: Llm::VivaGradeAssist.rubric_version_for(@submission.problem, strict: false))
      end
      # Check and mark under the row lock (see Llm::VivaGradeAssist#handle_error).
      @submission.with_lock do
        next if @submission.valid_viva_grade?
        @submission.update!(status: :grader_error,
                            grader_comment: "Grader error (retries exhausted): #{error.class.name}: #{error.message}")
      end
    rescue => e
      Rails.logger.error "on_retries_exhausted failed for VivaGradeAssistJob: #{e.class}: #{e.message}"
    end
  end
end
