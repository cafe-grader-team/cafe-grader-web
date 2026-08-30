module Llm
  # Comment-style assist job for the self-hosted provider. Resolved by
  # comments_controller#llm_assist as provider-class-name + 'Job'.
  # on_retries_exhausted (mark the Comment :error) is inherited from
  # CommentAssistJob.
  class SelfHostAssistJob < CommentAssistJob
    private

    def service_class
      Llm::SelfHostAssist
    end
  end
end
