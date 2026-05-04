# Compare current Submission state against the captured baseline WITHOUT
# touching the queue. Use this when sanity_verify timed out but the worker
# actually finished, or any time you want to re-read results without re-judging.
#
# Run:
#   bin/rails runner script/migrate_2023/sanity_compare.rb
#
# Options:
#   TOLERANCE=0.01       # absolute delta in pct points to count as exact match
#
# When the baseline was captured with a recent sanity_capture.rb, each entry
# carries the legacy grader_comment string (per-testcase result letters).
# Mismatches are then classified by what changed:
#   - limits_resolved: only T/M letters became P (faster machine, benign)
#   - score_regression: only P letters became something else (lost ground)
#   - mixed_changes: both directions
# Older baselines without grader_comment fall back to "score_mismatch".

require 'json'
require 'csv'

INPUT_PATH = File.expand_path('sanity_baseline.json', __dir__)
TOLERANCE  = (ENV['TOLERANCE'] || '0.01').to_f

# Letters whose "X -> P" transition we treat as benign drift. Per the grader's
# comment-letter convention (see CLAUDE.md):
#   P = pass, T = TLE, x = seg-fault or MLE, - = wrong, s = partial
# Only T -> P and x -> P count as machine-environment differences; everything
# else is a real score change.
LIMIT_LETTERS = %w[T x].freeze
PASS_LETTER   = 'P'

abort "Baseline not found: #{INPUT_PATH}" unless File.exist?(INPUT_PATH)

$stdout.sync = true
Rainbow.enabled = true   # force color when piped through tee
data = JSON.parse(File.read(INPUT_PATH))
entries = data['submissions']
captured_comments = entries.first&.key?('baseline_grader_comment')

puts '=' * 72
puts "SANITY COMPARE: #{entries.size} entries (read-only, no queueing)"
puts "Captured at:    #{data['captured_at']}"
puts "Tolerance:      #{TOLERANCE} pct points"
puts "Comments saved: #{captured_comments ? 'yes' : 'no (fall back to score_mismatch)'}"
puts '=' * 72

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

results = []
status_counts = Hash.new(0)

entries.each do |e|
  sub = Submission.find_by(id: e['sub_id'])
  unless sub
    results << { entry: e, classification: :missing }
    next
  end
  status_counts[sub.status] += 1
  expected = e['expected_pct'].to_f
  actual = sub.points.to_f
  delta = (expected - actual).abs

  classification =
    case sub.status
    when 'compilation_error'
      # Smoking gun: the captured submission DID compile and score in the
      # legacy run (otherwise it wouldn't be in our baseline at all). If it
      # now fails to compile, our migration almost certainly missed a manager
      # file or set the wrong main_filename / submission_filename.
      :compilation_error_regression
    when 'grader_error'
      # The new judge ran the binary but the checker errored. Usually means
      # the checker we attached doesn't match what the legacy judge invoked.
      :grader_error_regression
    when 'done'
      if delta <= TOLERANCE
        :exact_match
      elsif captured_comments
        classify_drift(e['baseline_grader_comment'], sub.grader_comment)
      else
        :score_mismatch
      end
    else
      :non_done_status   # submitted/evaluating — worker didn't finish
    end

  results << {
    entry: e,
    classification: classification,
    status: sub.status,
    actual: actual,
    delta: delta,
    current_comment: sub.grader_comment,
  }
end

# Tally by classification x kind
by_class = Hash.new { |h, k| h[k] = { 'full' => 0, 'partial' => 0 } }
results.each do |r|
  by_class[r[:classification]][r[:entry]['kind']] += 1
end

# Summary
puts ''
puts "Status distribution among current subs: #{status_counts.inspect}"
puts ''
puts 'BREAKDOWN by classification x kind:'
fmt = "  %-32s %8s %8s %8s"
puts format(fmt, 'classification', 'full', 'partial', 'total')
puts "  #{'-' * 60}"
order = %i[exact_match limits_resolved other_to_pass score_regression
           mixed_changes score_mismatch
           compilation_error_regression grader_error_regression
           non_done_status missing
           no_legacy_comment no_current_comment length_changed]
order.each do |c|
  bucket = by_class[c]
  next if bucket['full'] == 0 && bucket['partial'] == 0
  total = bucket['full'] + bucket['partial']
  puts format(fmt, c, bucket['full'], bucket['partial'], total)
end
puts "  #{'-' * 60}"
total_full    = entries.count { |e| e['kind'] == 'full' }
total_partial = entries.count { |e| e['kind'] == 'partial' }
puts format(fmt, 'TOTAL', total_full, total_partial, entries.size)

# Headline numbers
clean_classes  = %i[exact_match limits_resolved]
clean_count    = results.count { |r| clean_classes.include?(r[:classification]) }
real_mismatches = results.reject { |r| clean_classes.include?(r[:classification]) }
compile_regressions = results.count { |r| r[:classification] == :compilation_error_regression }
grader_regressions  = results.count { |r| r[:classification] == :grader_error_regression }
puts ''
puts "CLEAN (exact + limits_resolved):  #{clean_count}/#{entries.size}"
puts "REAL ISSUES:                      #{real_mismatches.size}/#{entries.size}"
if compile_regressions > 0
  puts Rainbow("  compilation_error_regression: #{compile_regressions}  (manager attachment is broken)").color(:red)
end
if grader_regressions > 0
  puts Rainbow("  grader_error_regression:      #{grader_regressions}  (checker attachment is broken)").color(:gold)
end

if real_mismatches.any?
  puts ''
  puts 'Detail (first 30 real issues):'
  drow = "  %-8s %-26s %-7s %-22s %-10s %-10s %s"
  puts format(drow, 'sub_id', 'problem', 'kind', 'classification', 'expected', 'actual', 'status')
  real_mismatches.first(30).each do |r|
    e = r[:entry]
    puts format(drow,
                e['sub_id'],
                e['problem_name'][0, 26],
                e['kind'],
                r[:classification],
                e['expected_pct'],
                r[:actual]&.round(4) || '-',
                r[:status] || '-')
  end
  puts "  ... #{real_mismatches.size - 30} more in the report file" if real_mismatches.size > 30
end

# Save full report
report_path = File.expand_path("sanity_report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json", __dir__)
File.write(report_path, JSON.pretty_generate({
  compared_at: Time.now.iso8601,
  baseline_captured_at: data['captured_at'],
  total_entries: entries.size,
  tolerance: TOLERANCE,
  comments_captured: captured_comments,
  status_counts: status_counts,
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
}))
puts ''
puts "Report saved to: #{report_path}"

# Also write a CSV (one row per result) for spreadsheet review.
csv_path = report_path.sub(/\.json\z/, '.csv')
CSV.open(csv_path, 'w', write_headers: true, headers: %w[
  sub_id problem_name kind user_id language_id classification
  expected actual delta status baseline_comment current_comment
]) do |csv|
  results.each do |r|
    e = r[:entry]
    csv << [
      e['sub_id'],
      e['problem_name'],
      e['kind'],
      e['user_id'],
      e['language_id'],
      r[:classification].to_s,
      e['expected_pct'],
      r[:actual],
      r[:delta]&.round(4),
      r[:status],
      e['baseline_grader_comment'],
      r[:current_comment],
    ]
  end
end
puts "CSV saved to:    #{csv_path}"
