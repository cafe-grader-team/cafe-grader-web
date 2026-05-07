module Llm
  # Abstract base: builds messages and parses responses for a single viva interview turn.
  # Provider-agnostic; speaks OpenAI-compatible chat-completion shape for both request
  # (messages: [{role, content}, ...]) and response (choices[0].message.content + usage{prompt_tokens, completion_tokens}).
  #
  # Deployment-specific branches must provide a concrete subclass that implements #execute_call
  # (e.g. Llm::VivaTurnGenieAssist on the chula_cp branch). See Llm::VivaTurnAssistJob for wiring.
  class VivaTurnAssist < Request
    DONE_SENTINEL = '[[VIVA_DONE]]'.freeze
    MAX_TOKENS    = 2048
    DEFAULT_MODEL = nil

    def initialize(submission:, turn:, model: nil, **args)
      @submission = submission
      @problem    = submission.problem
      @turn       = turn
      @model      = model.presence || self.class::DEFAULT_MODEL
      @error      = nil
      @other_args = args
    end

    private

    def provider_name
      'abstract'
    end

    def prepare_data
      {
        model:      @model,
        messages:   messages_array,
        max_tokens: MAX_TOKENS
      }
    end

    def messages_array
      msgs = [{role: 'system', content: assemble_system_prompt}]
      msgs << {role: 'user', content: build_first_user_content}
      msgs.concat(prior_turn_messages)
      consolidate_role_runs(msgs)
    end

    def scenario_message
      @problem.description.to_s.strip.presence || '(begin the interview)'
    end

    # The first user message carries the "case at hand": scenario text, any
    # grounding material from viva_grounding tags, and the problem PDF if
    # attached. Returns a plain string when there's only the scenario (simpler
    # wire shape); otherwise a multimodal content array.
    def build_first_user_content
      parts = [{type: 'text', text: scenario_message}]
      grounding = grounding_block
      parts << {type: 'text', text: grounding} if grounding
      pdf = pdf_attachment
      parts << pdf if pdf
      parts.length == 1 ? scenario_message : parts
    end

    # Concatenated viva_grounding tag payloads, with a markdown header so the
    # model can identify the section. Returns nil when no grounding tags exist.
    def grounding_block
      grounding = @problem.viva_grounding_tags.map(&:grounding_payload).reject(&:blank?).join("\n\n---\n\n")
      return nil if grounding.blank?
      "## Grounding Material\n\n#{grounding}"
    end

    # Backend-injected protocol directive. The model MUST include this exact
    # sentinel in its final message to trigger Llm::VivaGradeAssistJob via
    # the parsing in handle_response. Kept centralized here (rather than
    # baked into every llm_prompt tag) because it's a code contract, not
    # prompt-author guidance.
    def done_sentinel_directive
      "When you are satisfied you have enough signal to grade the student, " \
        "append exactly `#{DONE_SENTINEL}` at the very end of your final message to end the interview."
    end

    def assemble_system_prompt
      prompt = @problem.viva_prompt_tags.map(&:params).reject(&:blank?).join("\n\n")
      raise RuntimeError, "There is no llm_prompt tag attached to problem '#{@problem.name}' — viva needs a prompt tag" if prompt.blank?

      [prompt, done_sentinel_directive].join("\n\n")
    end

    # OpenAI chat-completions only accepts system/user/assistant/tool roles, so we
    # remap our DB role enum (which keeps `student` for transcript display) when
    # building the wire message list.
    def prior_turn_messages
      @prior_turn_messages ||= @submission.viva_turns.ordered.filter_map do |t|
        next if t.id == @turn&.id
        next if t.processing? || t.error?
        next if t.system?
        wire_role = t.student? ? 'user' : t.role
        {role: wire_role, content: t.content.to_s}
      end
    end

    def execute_call(data)
      raise NotImplementedError, "#{self.class} must implement #execute_call — configure a deployment-specific provider subclass"
    end

    def handle_response(response)
      parsed = JSON.parse(response.body)
      text   = parsed.dig('choices', 0, 'message', 'content').to_s
      done   = text.include?(DONE_SENTINEL)
      clean  = text.sub(DONE_SENTINEL, '').strip
      usage  = parsed['usage'] || {}

      @turn.update!(
        content:          clean,
        llm_model:        parsed['model'] || @model,
        llm_response_raw: response.body,
        token_count_in:   usage['prompt_tokens'],
        token_count_out:  usage['completion_tokens'],
        cost:             compute_cost(usage),
        status:           :ok
      )

      if done
        @submission.update!(status: :evaluating)
        Llm::VivaGradeAssistJob.perform_later(@submission, model: @model)
      end

      {done: done}
    end

    def handle_error
      @turn&.update!(status: :error, content: "LLM error: #{@error}")
    end

    # Subclasses should override to reflect their provider's pricing.
    def compute_cost(_usage)
      0.0
    end
  end
end
