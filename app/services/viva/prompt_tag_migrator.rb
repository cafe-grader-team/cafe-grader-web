module Viva
  # One-shot data migration for design D6 (2026-07-20 spec): move per-problem
  # llm_prompt pseudo-tags into problems.viva_prompt; re-kind genuinely shared
  # viva tags to viva_conduct. Report-first: only mutates when apply: true.
  class PromptTagMigrator
    def initialize(apply: false, io: $stdout)
      @apply = apply
      @io = io
    end

    def run
      @io.puts(@apply ? '== APPLYING ==' : '== DRY RUN (report only; run with APPLY=1 to execute) ==')
      ActiveRecord::Base.transaction do
        candidate_tags.each { |tag| process(tag) }
        post_check
        raise ActiveRecord::Rollback unless @apply
      end
      @io.puts '== done =='
    end

    private

    # llm_prompt tags attached to at least one viva problem.
    def candidate_tags
      Tag.where(kind: :llm_prompt)
         .joins(:problems).where(problems: {compilation_type: Problem.compilation_types[:viva_exam]})
         .distinct.order(:id).to_a
    end

    def process(tag)
      problems = tag.problems.distinct.to_a
      viva, non_viva = problems.partition(&:viva_exam?)

      if non_viva.any?
        @io.puts "DUAL-USE  tag ##{tag.id} '#{tag.name}': viva=#{viva.map(&:name).join(',')} non-viva=#{non_viva.map(&:name).join(',')} — MANUAL SPLIT REQUIRED, skipped"
      elsif viva.size == 1
        problem = viva.first
        existing = problem.viva_prompt.to_s
        incoming = tag.params.to_s
        if existing.present? && existing != incoming
          @io.puts "CONFLICT  tag ##{tag.id} '#{tag.name}' → problem '#{problem.name}' already has viva_prompt (existing #{existing.length} chars vs tag #{incoming.length} chars) — MANUAL REVIEW REQUIRED, skipped"
        else
          @io.puts "MOVE      tag ##{tag.id} '#{tag.name}' → problem '#{problem.name}'.viva_prompt (#{incoming.length} chars), tag deleted"
          problem.update!(viva_prompt: tag.params)
          problem.tags.delete(tag)
          tag.destroy!
        end
      else
        rubric_note = tag.params.to_s.match?(/^#+\s*Rubric\b/im) ? ' [CONTAINS # Rubric — decide: generic rubric stays shared or moves per-problem]' : ''
        @io.puts "RE-KIND   tag ##{tag.id} '#{tag.name}' → viva_conduct (shared by #{viva.size} vivas)#{rubric_note}"
        tag.update!(kind: :viva_conduct, public: false)
      end
    end

    def post_check
      Problem.where(compilation_type: :viva_exam).find_each do |p|
        errs = p.viva_setup_errors
        @io.puts "POST-CHECK FAIL problem '#{p.name}': #{errs.join('; ')}" if errs.any?
      end
    end
  end
end
