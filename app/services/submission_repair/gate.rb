# app/services/submission_repair/gate.rb
require 'diff/lcs'

# NOTE: reopened with `class`, not `module` — SubmissionRepair is already an
# ApplicationRecord subclass (app/models/submission_repair.rb), and Ruby
# raises `TypeError: SubmissionRepair is not a module` if a class is reopened
# with the `module` keyword. Nesting Gate inside the existing class works
# identically to nesting inside a module for constant-lookup purposes.
class SubmissionRepair
  # Deterministic, LLM-free budget gate for Near-Miss Grading. Pure function:
  # no I/O, no DB. Normalizes both sources, line-diffs them, and measures the
  # change against a dual cap (max changed lines AND max changed chars).
  # Any exception here is a bug — never rescued.
  #
  # Measurement rules (spec section 6):
  # * a paired modification (old line -> new line) counts as ONE changed line,
  #   and its char cost is the per-line Levenshtein distance
  # * an unpaired inserted/deleted line counts as one changed line and its
  #   full normalized length in chars
  class Gate
    Result = Struct.new(:verdict, :changed_lines, :changed_chars, :patch, keyword_init: true)

    def self.evaluate(original:, repaired:, budget_lines:, budget_chars:)
      o_lines = normalize_lines(original)
      r_lines = normalize_lines(repaired)
      return Result.new(verdict: :no_change, changed_lines: 0, changed_chars: 0, patch: '') if o_lines == r_lines

      changed_lines = 0
      changed_chars = 0
      patch_parts   = []
      Diff::LCS.sdiff(o_lines, r_lines).each do |c|
        case c.action
        when '!'
          changed_lines += 1
          changed_chars += levenshtein(c.old_element, c.new_element)
          patch_parts << "@#{c.old_position + 1}\n-#{c.old_element}\n+#{c.new_element}"
        when '-'
          changed_lines += 1
          changed_chars += c.old_element.length
          patch_parts << "@#{c.old_position + 1}\n-#{c.old_element}"
        when '+'
          changed_lines += 1
          changed_chars += c.new_element.length
          patch_parts << "@#{c.new_position + 1}\n+#{c.new_element}"
        end
      end

      verdict = (changed_lines <= budget_lines && changed_chars <= budget_chars) ? :accepted : :over_budget
      Result.new(verdict: verdict, changed_lines: changed_lines,
                 changed_chars: changed_chars, patch: patch_parts.join("\n"))
    end

    # CRLF/CR -> LF, strip trailing whitespace per line, drop trailing blank
    # lines (equivalent to "ensure single trailing newline" for comparison).
    def self.normalize_lines(src)
      lines = src.to_s.gsub("\r\n", "\n").tr("\r", "\n").split("\n", -1).map(&:rstrip)
      lines.pop while lines.any? && lines.last.empty?
      lines
    end

    # Plain DP Levenshtein; inputs are single source lines (short), so pure
    # Ruby is fast enough at batch scale.
    def self.levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?
      prev = (0..b.length).to_a
      a.each_char.with_index(1) do |ca, i|
        curr = [i]
        b.each_char.with_index(1) do |cb, j|
          curr << [prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + (ca == cb ? 0 : 1)].min
        end
        prev = curr
      end
      prev[b.length]
    end
  end
end
