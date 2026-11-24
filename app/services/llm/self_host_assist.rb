module Llm
  # Submission-assist provider backed by the self-hosted models. The per-model
  # provider map in llm.yml registers SERVED model names (what the picker
  # shows), e.g.  SelfHostAssist: qwen3.5,gemma-4-31b  — this class resolves
  # a served name back to its self_hosted_models entry. Dollar cost is 0.0
  # (department hardware); token usage is logged for visibility.
  class SelfHostAssist < CommentAssist
    def self.model_key_for(served_name)
      models = Rails.configuration.llm[:self_hosted_models] || {}
      pair = models.find { |_key, cfg| cfg[:model] == served_name }
      pair&.first
    end

    private

    def provider_name = 'self-host'

    # Department hardware: no per-call dollar figure, and 0.0 is the honest
    # answer (unlike a provider that has a price we failed to read).
    def compute_cost(_usage) = 0.0

    def execute_call(data)
      key = self.class.model_key_for(@model)
      raise ResponseError.new("no self_hosted_models entry serves model #{@model.inspect}") if key.nil?
      payload = JSON.parse(data, symbolize_names: true)
      response = SelfHostChat.new(model_key: key).chat(payload[:messages])
      log_usage(response)
      response
    end

    def log_usage(response)
      usage = JSON.parse(response.body)['usage']
      Rails.logger.info("SelfHostAssist model=#{@model} tokens_in=#{usage&.dig('prompt_tokens')} tokens_out=#{usage&.dig('completion_tokens')} cost=0.0")
    rescue JSON::ParserError
      nil # handle_response reports malformed bodies; logging must not preempt it
    end
  end
end
