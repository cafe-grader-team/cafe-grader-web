# Run BEFORE sanity_verify.rb. Captures baseline submissions (legacy points,
# legacy grader_comment) so a post-rejudge comparison can detect drift.
#
# Run AFTER migrate_tasks_v2.rb when using KIND filtering (it inspects
# Dataset.evaluation_type / score_type, which only exist post-migrate).
# Without KIND filtering, may also be run pre-migrate. The migrate's rescale
# step doesn't touch grader_comment, so post-migrate capture preserves the
# legacy comment string for comparison.
#
# Run:
#   bin/rails runner script/migrate_2023/sanity_capture.rb
#
# Options (env vars):
#   LIMIT_PROBLEMS=200      # number of problems to sample (0 = no cap)
#   RANDOM=1                # pick random problems instead of first-by-id
#   SUBS_PER_KIND=2         # how many full + how many partial per problem
#   KIND=custom_cafe        # filter to datasets with that eval_type or score_type
#                           # (comma-separated; values from each enum AND together)
#
# KIND values:
#   evaluation_type:  default, exact, relative, custom_cafe, custom_cms, postgres, custom_cms_raw
#   score_type:       sum, group_min, raw_sum

require 'json'

OUTPUT_PATH    = File.expand_path('sanity_baseline.json', __dir__)
LIMIT_PROBLEMS = (ENV['LIMIT_PROBLEMS'] || '200').to_i
RANDOMIZE      = ENV['RANDOM'] == '1'
SUBS_PER_KIND  = (ENV['SUBS_PER_KIND'] || '2').to_i

KIND_FILTER = (ENV['KIND'] || '').split(',').map(&:strip).reject(&:empty?)
EVAL_TYPES  = Dataset.evaluation_types.keys
SCORE_TYPES = Dataset.score_types.keys

eval_kinds  = KIND_FILTER & EVAL_TYPES
score_kinds = KIND_FILTER & SCORE_TYPES
unknown     = KIND_FILTER - EVAL_TYPES - SCORE_TYPES

if unknown.any?
  abort "Unknown KIND values: #{unknown.inspect}.\n  Allowed eval_type:  #{EVAL_TYPES.inspect}\n  Allowed score_type: #{SCORE_TYPES.inspect}"
end

# Pick up to n submissions for one problem and one kind, preferring different
# users (the earliest sub per user, ordered by that earliest submitted_at).
# If fewer than n distinct users qualify, backfills with extras from any user.
def pick_diverse(problem_id, fs, n, kind)
  base = Submission.where(problem_id: problem_id)
  base = case kind
         when :full    then base.where(points: fs)
         when :partial then base.where('points > 0 AND points < ?', fs)
         end

  top_user_ids = base.group(:user_id)
                     .order(Arel.sql('MIN(submitted_at) ASC'))
                     .limit(n)
                     .pluck(:user_id)
  selected = top_user_ids.filter_map { |uid| base.where(user_id: uid).order(:submitted_at).first }

  if selected.size < n
    extras = base.where.not(id: selected.map(&:id))
                 .order(:submitted_at)
                 .limit(n - selected.size).to_a
    selected.concat(extras)
  end
  selected
end

scope = Problem.joins(:submissions).distinct
if KIND_FILTER.any?
  scope = scope.joins('INNER JOIN datasets ON datasets.id = problems.live_dataset_id')
  if eval_kinds.any?
    vals = eval_kinds.map { |k| Dataset.evaluation_types[k] }
    scope = scope.where('datasets.evaluation_type IN (?)', vals)
  end
  if score_kinds.any?
    vals = score_kinds.map { |k| Dataset.score_types[k] }
    scope = scope.where('datasets.score_type IN (?)', vals)
  end
end
scope = RANDOMIZE ? scope.order('RAND()') : scope.order('problems.id')
scope = scope.limit(LIMIT_PROBLEMS) if LIMIT_PROBLEMS > 0

picked_problems = scope.to_a
puts "Scanning #{picked_problems.size} problems"
puts "  LIMIT_PROBLEMS=#{LIMIT_PROBLEMS}, RANDOM=#{RANDOMIZE}, SUBS_PER_KIND=#{SUBS_PER_KIND}"
puts "  KIND filter eval_type=#{eval_kinds.inspect}  score_type=#{score_kinds.inspect}" if KIND_FILTER.any?

baseline = []
got_full_dist = Hash.new(0)
got_partial_dist = Hash.new(0)

picked_problems.each do |p|
  fs = p.full_score.to_i
  next if fs <= 0

  fulls = pick_diverse(p.id, fs, SUBS_PER_KIND, :full)
  partials = pick_diverse(p.id, fs, SUBS_PER_KIND, :partial)
  got_full_dist[fulls.size] += 1
  got_partial_dist[partials.size] += 1

  fulls.each do |s|
    baseline << {
      sub_id: s.id,
      problem_id: p.id,
      problem_name: p.name,
      user_id: s.user_id,
      baseline_points: s.points.to_f,
      baseline_full_score: fs,
      expected_pct: (s.points.to_f / fs * 100).round(4),
      baseline_grader_comment: s.grader_comment,
      kind: 'full',
      language_id: s.language_id,
    }
  end

  partials.each do |s|
    baseline << {
      sub_id: s.id,
      problem_id: p.id,
      problem_name: p.name,
      user_id: s.user_id,
      baseline_points: s.points.to_f,
      baseline_full_score: fs,
      expected_pct: (s.points.to_f / fs * 100).round(4),
      baseline_grader_comment: s.grader_comment,
      kind: 'partial',
      language_id: s.language_id,
    }
  end
end

File.write(OUTPUT_PATH, JSON.pretty_generate({
  captured_at: Time.zone.now.iso8601,
  limit_problems: LIMIT_PROBLEMS,
  randomize: RANDOMIZE,
  subs_per_kind: SUBS_PER_KIND,
  kind_filter: { eval_type: eval_kinds, score_type: score_kinds },
  problems_scanned: picked_problems.size,
  full_count_distribution: got_full_dist.sort.to_h,
  partial_count_distribution: got_partial_dist.sort.to_h,
  submissions: baseline,
}))

puts ''
puts "Captured #{baseline.size} submissions across #{picked_problems.size} problems"
puts "  full subs:    #{baseline.count { |s| s[:kind] == 'full' }}"
puts "  partial subs: #{baseline.count { |s| s[:kind] == 'partial' }}"
puts ''
puts "Distribution of full subs captured per problem:"
got_full_dist.sort.each { |n, c| puts "  #{n} full   x #{c} problems" }
puts "Distribution of partial subs captured per problem:"
got_partial_dist.sort.each { |n, c| puts "  #{n} partial x #{c} problems" }
puts ''
puts "Distinct users among captured subs: #{baseline.map { |s| s[:user_id] }.uniq.size}"
puts ''
puts "Saved baseline to: #{OUTPUT_PATH}"
