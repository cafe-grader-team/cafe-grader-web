# Run AFTER migrate_tasks_v2.rb.
#
# Reads the baseline produced by sanity_capture.rb, rejudges each captured
# submission via add_judge_job, polls until grading completes, and compares
# the new (rejudged) points against the expected percentage from the baseline.
#
# Requires the judge worker process to be running.
#
# Run:
#   bin/rails runner script/migrate_2023/sanity_verify.rb
#
# Options (env vars):
#   TOLERANCE=0.01       # acceptable absolute delta in points (default 0.01)
#   POLL_INTERVAL=5      # seconds between status polls (default 5)
#   TIMEOUT=1800         # seconds before giving up on pending jobs (default 1800)
#   DRY_RUN=1            # print plan, do not enqueue or wait

require 'json'

INPUT_PATH    = File.expand_path('sanity_baseline.json', __dir__)
TOLERANCE     = (ENV['TOLERANCE']     || '0.01').to_f
POLL_INTERVAL = (ENV['POLL_INTERVAL'] || '5').to_i
TIMEOUT       = (ENV['TIMEOUT']       || '1800').to_i
DRY_RUN       = ENV['DRY_RUN'] == '1'

abort "Baseline not found: #{INPUT_PATH}\nRun sanity_capture.rb BEFORE migrating." unless File.exist?(INPUT_PATH)

$stdout.sync = true
Rainbow.enabled = true
data = JSON.parse(File.read(INPUT_PATH))
entries = data['submissions']

puts '=' * 72
puts "SANITY VERIFY: #{entries.size} captured baseline submissions"
puts "Captured at:    #{data['captured_at']}"
puts "Tolerance:      #{TOLERANCE} pct points"
puts "Poll interval:  #{POLL_INTERVAL}s   Timeout: #{TIMEOUT}s"
puts "Dry run:        #{DRY_RUN}"
puts '=' * 72

# --- Phase 1: queue rejudges ---
puts ''
puts '--- Phase 1: queueing rejudges ---'
queued = []
skipped = []

entries.each do |e|
  sub = Submission.find_by(id: e['sub_id'])
  unless sub
    skipped << { entry: e, reason: 'submission_missing' }
    next
  end
  unless sub.problem.live_dataset
    skipped << { entry: e, reason: 'no_live_dataset' }
    next
  end

  if DRY_RUN
    queued << { entry: e, sub_id: sub.id }
    next
  end

  begin
    sub.add_judge_job
    queued << { entry: e, sub_id: sub.id }
    print '.'
  rescue => err
    skipped << { entry: e, reason: "queue_error: #{err.class}: #{err.message[0, 80]}" }
  end
end
puts ''
puts "Queued:  #{queued.size}"
puts "Skipped: #{skipped.size}"
skipped.first(10).each { |s| puts "  skip ##{s[:entry]['sub_id']} (#{s[:entry]['problem_name']}): #{s[:reason]}" }

if DRY_RUN
  puts ''
  puts 'DRY_RUN: stopping before wait/compare phase.'
  exit 0
end

if queued.empty?
  puts 'Nothing queued, exiting.'
  exit 0
end

# --- Phase 2: wait for terminal status ---
puts ''
puts '--- Phase 2: waiting for grading ---'
TERMINAL = %w[done compilation_error grader_error].freeze
start = Time.now
loop do
  # Pass string keys, not integer values: Rails enum where-clauses resolve
  # string keys via the enum mapping but treat integer values inconsistently
  # in Rails 7+, leading to a query that never filters anything.
  pending_ids = Submission.where(id: queued.map { |q| q[:sub_id] })
                          .where.not(status: TERMINAL)
                          .pluck(:id)
  elapsed = (Time.now - start).to_i
  puts "  [#{elapsed}s] pending: #{pending_ids.size}/#{queued.size}"
  break if pending_ids.empty?
  if elapsed >= TIMEOUT
    puts "  TIMEOUT: #{pending_ids.size} still pending"
    break
  end
  sleep POLL_INTERVAL
end

# --- Phase 3: compare ---
# Same classification logic as sanity_compare.rb. Kept in lockstep on purpose.
# Letter convention is documented in CLAUDE.md (Submission grader_comment).
# Only T -> P and x -> P count as benign machine-environment drift.
LIMIT_LETTERS = %w[T x].freeze
PASS_LETTER   = 'P'

def classify_drift(legacy_comment, current_comment)
  return :no_legacy_comment   if legacy_comment.nil? || legacy_comment.empty?
  return :no_current_comment  if current_comment.nil? || current_comment.empty?
  return :length_changed      if legacy_comment.length != current_comment.length

  diffs = legacy_comment.chars.zip(current_comment.chars).reject { |a, b| a == b }
  return :exact_match if diffs.empty?

  to_pass   = diffs.select { |_, b| b == PASS_LETTER }
  from_pass = diffs.select { |a, _| a == PASS_LETTER }

  if from_pass.empty? && to_pass.size == diffs.size
    sources = to_pass.map { |a, _| a }.uniq
    if (sources - LIMIT_LETTERS).empty?
      :limits_resolved
    else
      :other_to_pass
    end
  elsif to_pass.empty? && from_pass.size == diffs.size
    :score_regression
  else
    :mixed_changes
  end
end

puts ''
puts '--- Phase 3: comparing scores ---'
captured_comments = entries.first&.key?('baseline_grader_comment')
results = []
queued.each do |q|
  sub = Submission.find(q[:sub_id])
  expected = q[:entry]['expected_pct'].to_f
  actual = sub.points.to_f
  delta = (expected - actual).abs

  classification =
    case sub.status
    when 'compilation_error'
      :compilation_error_regression
    when 'grader_error'
      :grader_error_regression
    when 'done'
      if delta <= TOLERANCE
        :exact_match
      elsif captured_comments
        classify_drift(q[:entry]['baseline_grader_comment'], sub.grader_comment)
      else
        :score_mismatch
      end
    else
      :non_done_status
    end

  results << {
    entry: q[:entry],
    classification: classification,
    status: sub.status,
    actual: actual,
    delta: delta,
    current_comment: sub.grader_comment,
  }
end

by_class = Hash.new { |h, k| h[k] = { 'full' => 0, 'partial' => 0 } }
results.each { |r| by_class[r[:classification]][r[:entry]['kind']] += 1 }

puts ''
puts 'BREAKDOWN by classification x kind:'
fmt = "  %-32s %8s %8s %8s"
puts format(fmt, 'classification', 'full', 'partial', 'total')
puts "  #{'-' * 60}"
order = %i[exact_match limits_resolved other_to_pass score_regression
           mixed_changes score_mismatch
           compilation_error_regression grader_error_regression
           non_done_status no_legacy_comment no_current_comment length_changed]
order.each do |c|
  b = by_class[c]
  next if b['full'] == 0 && b['partial'] == 0
  puts format(fmt, c, b['full'], b['partial'], b['full'] + b['partial'])
end
puts "  #{'-' * 60}"
total_full    = queued.count { |q| q[:entry]['kind'] == 'full' }
total_partial = queued.count { |q| q[:entry]['kind'] == 'partial' }
puts format(fmt, 'TOTAL', total_full, total_partial, queued.size)

clean_classes = %i[exact_match limits_resolved]
clean_count = results.count { |r| clean_classes.include?(r[:classification]) }
real_mismatches = results.reject { |r| clean_classes.include?(r[:classification]) }
compile_regressions = results.count { |r| r[:classification] == :compilation_error_regression }
grader_regressions  = results.count { |r| r[:classification] == :grader_error_regression }
puts ''
puts "CLEAN (exact + limits_resolved):  #{clean_count}/#{queued.size}"
puts "REAL ISSUES:                      #{real_mismatches.size}/#{queued.size}"
if compile_regressions > 0
  puts Rainbow("  compilation_error_regression: #{compile_regressions}  (manager attachment is broken)").color(:red)
end
if grader_regressions > 0
  puts Rainbow("  grader_error_regression:      #{grader_regressions}  (checker attachment is broken)").color(:gold)
end
puts "SKIPPED (Phase 1):                #{skipped.size}/#{entries.size}"

if real_mismatches.any?
  puts ''
  puts 'Detail (first 30 real issues):'
  drow = "  %-8s %-26s %-7s %-22s %-10s %-10s %s"
  puts format(drow, 'sub_id', 'problem', 'kind', 'classification', 'expected', 'actual', 'status')
  real_mismatches.first(30).each do |r|
    e = r[:entry]
    puts format(drow, e['sub_id'], e['problem_name'][0, 26], e['kind'],
                r[:classification], e['expected_pct'], r[:actual]&.round(4) || '-', r[:status] || '-')
  end
  puts "  ... #{real_mismatches.size - 30} more in the report file" if real_mismatches.size > 30
end

# Save report
report_path = File.expand_path("sanity_report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json", __dir__)
File.write(report_path, JSON.pretty_generate({
  verified_at: Time.now.iso8601,
  baseline_captured_at: data['captured_at'],
  total_baseline: entries.size,
  queued: queued.size,
  skipped_count: skipped.size,
  tolerance: TOLERANCE,
  comments_captured: captured_comments,
  by_classification: by_class,
  results: results.map { |r|
    {
      sub_id: r[:entry]['sub_id'],
      problem_name: r[:entry]['problem_name'],
      kind: r[:entry]['kind'],
      classification: r[:classification].to_s,
      expected: r[:entry]['expected_pct'],
      actual: r[:actual],
      delta: r[:delta],
      status: r[:status],
      baseline_comment: r[:entry]['baseline_grader_comment'],
      current_comment: r[:current_comment],
    }
  },
  skipped: skipped,
}))
puts ''
puts "Report saved to: #{report_path}"
