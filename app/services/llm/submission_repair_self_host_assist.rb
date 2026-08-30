module Llm
  # Self-hosted concrete repair provider. Model selection is pure config:
  # model_key (rake SERVICE=) -> self_hosted_models entry, default from
  # self_hosted_default. Dollar cost is 0.0 on department hardware; token
  # counts are still recorded by the base engine.
  class SubmissionRepairSelfHostAssist < SubmissionRepairAssist
    private

    def provider_name = 'self-host'

    # Verified against live sglang (2026-07-30 pilot): PDF content parts fail
    # in BOTH wire shapes — bare-string image_url is rejected by request
    # validation, and object-form {url:} passes validation but errors in the
    # image loader (a PDF is not an image). Self-host repair prompts are
    # therefore text-only: verdict + source.
    def include_statement_pdf? = false

    def chat_client
      @chat_client ||= SelfHostChat.new(model_key: @other_args[:model_key])
    end

    def execute_chat(messages)
      chat_client.chat(messages)
    end

    def model_name_for_record = chat_client.model_name
  end
end
