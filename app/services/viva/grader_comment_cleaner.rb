module Viva
  # One-off cleanup for viva submissions graded before the marker change: the
  # success path used to copy the LLM narrative (300–450 chars) into
  # submissions.grader_comment, a compact verdict field the main list and the
  # admin tables print inline. Rewrites those rows to
  # Submission#viva_result_marker; the narrative itself stays untouched on
  # viva_grades.narrative. Report-first: only mutates when apply: true.
  #
  # Rows whose grader_comment does NOT contain the narrative are left alone
  # and listed — they may hold hand-edited or error text.
  class GraderCommentCleaner
    def initialize(apply: false, io: $stdout)
      @apply = apply
      @io = io
    end

    def run
      @io.puts(@apply ? '== APPLYING ==' : '== DRY RUN (report only; run with APPLY=1 to execute) ==')
      counts = Hash.new(0)
      candidates.find_each { |sub| counts[process(sub)] += 1 }
      @io.puts "== done: #{%i[rewrite already skip].map { |k| "#{k}=#{counts[k]}" }.join(' ')} =="
      counts
    end

    private

    def candidates
      Submission.joins(:viva_grade).where(status: :done).includes(:viva_grade, :user, :problem)
    end

    def process(sub)
      narrative = sub.viva_grade.narrative.to_s
      comment   = sub.grader_comment.to_s
      marker    = sub.viva_result_marker
      if comment == marker
        @io.puts "ALREADY   ##{sub.id} #{who(sub)}: grader_comment is already '#{marker}'"
        :already
      elsif narrative.present? && comment.include?(narrative)
        @io.puts "REWRITE   ##{sub.id} #{who(sub)}: narrative copy (#{comment.length} chars) -> '#{marker}'"
        sub.update_columns(grader_comment: marker) if @apply
        :rewrite
      else
        @io.puts "SKIP      ##{sub.id} #{who(sub)}: grader_comment differs from narrative, left alone: #{comment[0, 60].inspect}"
        :skip
      end
    end

    def who(sub)
      "#{sub.user&.login}/#{sub.problem&.name}"
    end
  end
end
