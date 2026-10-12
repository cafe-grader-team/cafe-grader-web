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
    # that stores it pays 1.25x). LiteLLM passes the key through; Gemini
    # ignores it. `prompt_cache: false` in llm.yml's ai_gateway block turns it
    # off, e.g. for a gateway that rejects unknown keys on content parts.
    def prompt_cache_marker
      return {} if self.class.gateway_config[:prompt_cache] == false
      {cache_control: {type: 'ephemeral'}}
    end
  end
end
