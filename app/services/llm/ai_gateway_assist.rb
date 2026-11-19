module Llm
  # Hosted-gateway concrete subclass for comment-on-submission. Register
  # served models in llm.yml's per-model map (AiGatewayAssist: model-a,model-b)
  # to expose them in the assist picker beside other providers; anything
  # outside the configured roster is clamped back to the role default —
  # GenieAssist's PERMITTED_MODEL guard with config as the source of truth.
  class AiGatewayAssist < CommentAssist
    include AiGatewayTransport

    GATEWAY_ROLE = :assist

    private

    def prepare_data
      @model = gateway_default_model unless self.class.gateway_models.include?(@model.to_s)
      super
    end

    # Prompt caching on the problem-material boundary (measured through the
    # Chula AI Gateway 2026-10-09, doc/Assist-History.md): Claude keeps
    # everything up to the marked part for 5 minutes, and the next request on
    # the same problem pays a tenth of the input price for it (the request
    # that stores it pays 1.25x). `prompt_cache: false` in llm.yml's
    # ai_gateway block turns it off, e.g. for a gateway that rejects unknown
    # keys on content parts.
    #
    # Only Claude models get the marker. Through LiteLLM a Gemini model does
    # not ignore it: the key becomes a request for Gemini's explicit cache,
    # which refuses material below its minimum size — HTTP 400, "The minimum
    # token count to start explicit caching is 4096" (gemini-3.7-flash,
    # gemini-4-argon, gemini-4-hydrogen; 2026-11-15) — so every request on a
    # problem with no statement PDF and small managers failed.
    PROMPT_CACHE_MODEL = /claude/i

    def prompt_cache_marker
      return {} if self.class.gateway_config[:prompt_cache] == false
      return {} unless @model.to_s.match?(PROMPT_CACHE_MODEL)
      {cache_control: {type: 'ephemeral'}}
    end
  end
end
