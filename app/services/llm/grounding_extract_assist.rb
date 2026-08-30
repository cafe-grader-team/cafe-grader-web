module Llm
  # Abstract base: a one-shot multimodal pass that turns a GroundingMaterial's
  # attached PDF(s) into a faithful-but-compact markdown DRAFT for the author
  # to review (design D4, docs/superpowers/specs/2026-07-20-viva-deployment-
  # readiness-design.md). Provider-agnostic; speaks the same OpenAI-compatible
  # chat-completion shape as the viva assist classes (messages in, choices[0]
  # .message.content + usage out).
  #
  # The draft is written to GroundingMaterial#extraction_draft, NEVER to
  # #body — Thai slide extraction is lossy and the author's explicit save is
  # the only path that can make a body live (see GroundingMaterialsController
  # and the edit view's "Copy draft into Body" control, which only prefills
  # the form field client-side).
  #
  # Deployment-specific branches must provide a concrete subclass that
  # implements #execute_call (e.g. Llm::GroundingExtractGenieAssist on the
  # chula_cp branch). See Llm::GroundingExtractJob for wiring.
  class GroundingExtractAssist < Request
    # Generous on purpose: this is a one-shot background job (not a per-turn
    # interactive call), source decks can run 30-50+ slides, and a truncated
    # draft is worse than a slow one — the author is reviewing this once,
    # not paying its latency on every turn like the viva turn/grade calls.
    MAX_TOKENS = 8192
    DEFAULT_MODEL = nil

    INSTRUCTION = <<~TXT.freeze
      Convert the attached PDF(s) into a single faithful-but-compact Markdown
      document for reuse as grounding reference material in an oral exam
      ("viva") system.

      Rules:
      - Preserve ALL technical content: definitions, formulas, numbers,
        named theorems/algorithms, code listings, and data in tables.
      - Condense boilerplate: repeated slide headers/footers, title/agenda/
        table-of-contents slides, page numbers, decorative content.
      - Describe each figure, diagram, or photo briefly (one to two
        sentences) — do not skip figures, but do not attempt to redraw them.
      - Preserve the source language exactly. If the source is Thai, keep
        the extracted text in Thai; do not translate.
      - Use Markdown headings/lists/tables to mirror the source structure
        where it helps readability.
      - Output ONLY the resulting Markdown document — no preamble, no
        commentary, no code fence wrapping the whole output.
    TXT

    # Overrides Request#initialize entirely (does not call super): this
    # service has no Submission/Problem, only a GroundingMaterial. Mirrors
    # the same override pattern as Llm::VivaTurnAssist#initialize.
    def initialize(grounding_material:, model: nil, **args)
      @grounding_material = grounding_material
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

    # A single user message: instruction text + one image_url part per
    # attached PDF (encode_pdf_part, shared with the viva assist classes and
    # GroundingMaterial#grounding_file_parts).
    def messages_array
      [{role: 'user', content: user_content}]
    end

    def user_content
      parts = [{type: 'text', text: INSTRUCTION}]
      parts.concat(pdf_parts)
      parts
    end

    def pdf_parts
      @grounding_material.files.filter_map { |f| self.class.encode_pdf_part(f) }
    end

    def execute_call(data)
      raise NotImplementedError, "#{self.class} must implement #execute_call — configure a deployment-specific provider subclass"
    end

    # Writes the extracted markdown into extraction_draft. Never touches
    # body. extraction_requested_at is left as-is (it records when the run
    # was last kicked off, not whether one is in flight — see the edit view,
    # which shows "in progress" only while extraction_draft is still blank).
    def handle_response(response)
      parsed  = JSON.parse(response.body)
      content = parsed.dig('choices', 0, 'message', 'content')
      if content.nil? || content.to_s.strip.empty?
        raise ResponseError.new(
          "Empty or missing choices[0].message.content in grounding extraction response from #{provider_name}",
          body: response&.body
        )
      end
      @grounding_material.update!(extraction_draft: content.to_s.strip)
    end

    # Leaves a readable failure note in extraction_draft (rather than nil-ing
    # it) so the edit view's draft panel surfaces the failure instead of
    # falling back to a silent, indefinite "in progress" line.
    def handle_error
      @grounding_material&.update!(extraction_draft: "EXTRACTION FAILED: #{@error}")
    end
  end
end
