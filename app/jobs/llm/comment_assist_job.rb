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
  end
end
