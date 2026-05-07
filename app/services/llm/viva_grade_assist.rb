module Llm
  # Abstract base: grades a completed viva transcript against the problem's rubric
  # and writes VivaGrade + updates Submission. Provider-agnostic; speaks OpenAI-compatible
  # chat-completion shape. Deployment branches provide a concrete #execute_call subclass.
  class VivaGradeAssist < Request
    MAX_TOKENS    = 2048
    DEFAULT_MODEL = nil

    def initialize(submission:, model: nil, **args)
      @submission = submission
      @problem    = submission.problem
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
      msgs = [
        {role: 'system', content: grading_system_prompt},
        {role: 'user',   content: scenario_message},
        {role: 'user',   content: transcript_payload}
      ]
      consolidate_role_runs(msgs)
    end

    def scenario_message
      @problem.description.to_s.strip.presence || '(no scenario provided)'
    end

    def grading_system_prompt
      <<~PROMPT
        You are a strict but fair grader for an oral programming exam. Evaluate the student's understanding based on the interview transcript.

        The user message contains the scenario the student was interviewed on (at the top), followed by the interview transcript to grade (below).

        Respond ONLY with valid JSON matching this schema (no markdown fences, no prose):
        {
          "total_points": <number 0-100>,
          "narrative": "<2-3 sentences of feedback to the student>",
          "rubric": {
            "<criterion>": <number 0-100>,
            ...
          }
        }

        Use the rubric and grounding context below as authoritative:

        #{assemble_context}
      PROMPT
    end

    def assemble_context
      prompt    = @problem.viva_prompt_tags.map(&:params).reject(&:blank?).join("\n\n")
      raise RuntimeError, "There is no llm_prompt tag attached to problem '#{@problem.name}' — viva needs a prompt tag" if prompt.blank?

      grounding = @problem.viva_grounding_tags.map(&:grounding_payload).reject(&:blank?).join("\n\n---\n\n")
      [prompt, grounding].reject(&:blank?).join("\n\n")
    end

    # Student turns are remapped from the DB role enum to the OpenAI wire role,
    # so the transcript reads USER:/ASSISTANT: rather than mixing in STUDENT:.
    def transcript_payload
      turns = @submission.viva_turns.ordered.reject { |t| t.system? || t.processing? || t.error? }
      lines = turns.map do |t|
        wire_role = t.student? ? 'user' : t.role
        "#{wire_role.upcase}: #{t.content}"
      end
      "Transcript:\n\n#{lines.join("\n\n")}"
    end

    def execute_call(data)
      raise NotImplementedError, "#{self.class} must implement #execute_call — configure a deployment-specific provider subclass"
    end

    def handle_response(response)
      parsed = JSON.parse(response.body)
      text   = parsed.dig('choices', 0, 'message', 'content').to_s
      json   = text.match(/\{.*\}/m)&.[](0)
      raise ResponseError.new('no JSON object found in response', body: response&.body) unless json

      data  = JSON.parse(json)
      usage = parsed['usage'] || {}

      grade = @submission.viva_grade || @submission.build_viva_grade
      grade.assign_attributes(
        score_json:       data['rubric']&.to_json,
        total_points:     data['total_points'],
        narrative:        data['narrative'],
        llm_model:        parsed['model'] || @model,
        llm_response_raw: response.body,
        cost:             compute_cost(usage),
        graded_at:        Time.zone.now
      )
      grade.save!

      @submission.update!(
        points:         data['total_points'],
        status:         :done,
        graded_at:      Time.zone.now,
        grader_comment: data['narrative']
      )

      {ok: true}
    end

    def handle_error
      @submission&.update!(status: :grader_error, grader_comment: "Grader error: #{@error}")
    end

    def compute_cost(_usage)
      0.0
    end
  end
end
