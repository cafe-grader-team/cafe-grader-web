module Llm
  # Marker base for comment-on-submission style LLM jobs. Adds nothing beyond
  # RequestJob today; exists so deployment-specific subclasses (e.g.
  # GenieAssistJob on chula_cp) can express "this is a comment-style job"
  # in their parent class. If you find yourself adding behavior here that
  # belongs on every LLM job, push it up to RequestJob instead.
  class CommentAssistJob < RequestJob
    private

    def service_class
      raise NotImplementedError, "#{self.class} must implement #service_class — typically a subclass of Llm::CommentAssist"
    end

    # Mark the placeholder Comment as :error after retries are exhausted.
    # Subclass concrete jobs (e.g. GenieAssistJob on chula_cp) inherit this
    # without override; the comment_assist flow enqueues with comment: in
    # job_args, matching the parameter pulled out here.
    def on_retries_exhausted(error)
      comment = @job_args&.fetch(:comment, nil)
      return unless comment
      # RequestJob#perform reuses this hook for NON-retryable failures too, but
      # there the service's own handle_error has already marked the comment —
      # don't relabel it "retries exhausted" or stack a second error block.
      return if comment.reload.error?
      comment.update(status: 'error',
                     title:  'Assistant Error (retries exhausted)',
                     body:   "#{comment.body}\n\nLLM error (retries exhausted): #{error.class.name}: #{error.message}")
    rescue => e
      Rails.logger.error "on_retries_exhausted failed for CommentAssistJob: #{e.class}: #{e.message}"
    end
  end
end
