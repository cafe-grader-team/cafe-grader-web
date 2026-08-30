module Replay
  # Pure classifier: compares a stored grading string against a fresh re-grade.
  # Only T->P and x->P (machine speed / memory) are benign; everything else is a
  # real mismatch. Grading chars: P pass, T tle, x invalid/mle, - wrong, s partial.
  module ReplayDiff
    module_function

    BENIGN = [%w[T P].freeze, %w[x P].freeze].freeze

    def classify(orig_gc, orig_points, new_gc, new_points)
      orig_gc = orig_gc.to_s
      new_gc  = new_gc.to_s
      if orig_gc.length != new_gc.length
        return { verdict: :structural, positions: [], points: [orig_points, new_points],
                 note: "grader_comment length differs (#{orig_gc.length} vs #{new_gc.length})" }
      end

      positions = []
      orig_gc.chars.each_with_index do |from, i|
        to = new_gc[i]
        next if from == to
        kind = BENIGN.include?([from, to]) ? :benign : :mismatch
        positions << { i: i, from: from, to: to, kind: kind }
      end

      verdict = if positions.empty?
        :exact
      elsif positions.all? { |p| p[:kind] == :benign }
        :benign
      else
        :mismatch
      end
      { verdict: verdict, positions: positions, points: [orig_points, new_points] }
    end
  end
end
