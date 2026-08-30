module Llm
  # Thin OpenAI-compatible chat client for the department's self-hosted
  # models. Model identity is config data: entries live in config/llm.yml
  # under self_hosted_models, keyed by operator-chosen labels — no class,
  # method, or constant here names a specific model. No auth: endpoints are
  # intranet-only.
  #
  # Operational contract (ported from cp-api docs/llm-api.md):
  # * never send repetition_penalty (degrades reasoning traces)
  # * max_tokens >= 4096 (reasoning tokens count against the budget)
  # * responses may carry reasoning_content alongside content — ignored
  # * connection refused on a swap-slot port is NORMAL operation (the model
  #   is swapped out); it surfaces as Faraday::ConnectionFailed, which the
  #   Llm retry taxonomy already treats as retryable
  class SelfHostChat
    class ConfigError < StandardError; end

    MIN_MAX_TOKENS = 4096

    # A near-cap non-streaming reasoning generation on a shared box
    # legitimately exceeds the stock 300s once max_tokens is 16384
    # (observed: transient read timeouts across providers in the 2026-07
    # batches) — double it for this transport only.
    READ_TIMEOUT = 600

    attr_reader :model_key, :entry

    def initialize(model_key: nil)
      models = Rails.configuration.llm[:self_hosted_models]
      raise ConfigError, 'llm.yml: self_hosted_models is not configured' if models.blank?
      key = (model_key.presence || Rails.configuration.llm[:self_hosted_default]).to_s
      raise ConfigError, 'no model key given and self_hosted_default is blank' if key.blank?
      @model_key = key.to_sym
      @entry = models[@model_key]
      raise ConfigError, "unknown self-hosted model key: #{key} (known: #{models.keys.join(', ')})" if @entry.blank?
    end

    def model_name = entry[:model]

    # POST a chat completion. Returns the raw Faraday response; callers
    # parse response.body themselves (matching the CommentAssist contract).
    def chat(messages, temperature: 0.7)
      payload = {
        model:       model_name,
        messages:    messages,
        temperature: temperature,
        max_tokens:  [entry[:max_tokens].to_i, MIN_MAX_TOKENS].max,
        stream:      false
      }
      connection.post(entry[:completion_path] || '/v1/chat/completions') do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = payload.to_json
      end
    end

    def served_model_ids
      resp = connection.get('/v1/models')
      JSON.parse(resp.body).fetch('data', []).map { |m| m['id'] }
    end

    # The DGX echoes the payload model string without validating it, so a
    # redeployed port could silently answer as a different model — fatal for
    # research-run comparability. Batch runs call this once before starting.
    def verify_model!
      served = served_model_ids
      return true if served.include?(model_name)
      raise ConfigError, "#{model_key}: endpoint #{entry[:base_url]} serves #{served.inspect} but config expects #{model_name.inspect}"
    end

    private

    def connection
      @connection ||= Llm::Request.connection(entry[:base_url], read_timeout: READ_TIMEOUT)
    end
  end
end
