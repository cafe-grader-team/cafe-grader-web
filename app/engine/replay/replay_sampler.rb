module Replay
  module ReplaySampler
    module_function

    # Up to `limit` of the problem's graded submissions, stratified across
    # zero / partial / full score buckets. Skips submissions graded before the
    # live dataset's updated_at (their stored grade predates the dataset we clone).
    def sample(problem, limit: 100, languages: nil)
      ds = problem.live_dataset
      cutoff = ds&.updated_at
      scope = problem.submissions.where.not(points: nil)
      scope = scope.joins(:language).where(languages: { name: languages }) if languages.present?
      graded = scope.order(:id).to_a
      fresh, stale = graded.partition do |s|
        cutoff.nil? || s.graded_at.nil? || s.graded_at >= cutoff
      end

      picked = round_robin(bucketize(problem, fresh).values, limit)
      { submissions: picked, skipped_stale: stale.size,
        buckets: bucketize(problem, picked).transform_values(&:size) }
    end

    # Split submissions into zero / partial / full score buckets. "full" uses
    # the problem's full_score (matching ProblemStat's solved definition),
    # falling back to the batch's own max only when full_score is nil/0 — the
    # goal is a spread across outcomes, not an exact ceiling.
    def bucketize(problem, subs)
      full_score = problem.full_score.to_f
      full_score = (subs.map { |s| s.points.to_f }.max || 0.0) if full_score <= 0
      buckets = { zero: [], partial: [], full: [] }
      subs.each do |s|
        pts = s.points.to_f
        key = if pts <= 0 then :zero
        elsif full_score.positive? && pts >= full_score then :full
        else :partial
        end
        buckets[key] << s
      end
      buckets
    end

    # Interleave lists so `limit` picks are spread across non-empty buckets.
    def round_robin(lists, limit)
      lists = lists.map(&:dup)
      result = []
      i = 0
      while result.size < limit && lists.any?(&:any?)
        list = lists[i % lists.size]
        result << list.shift if list.any?
        i += 1
      end
      result
    end
  end
end
