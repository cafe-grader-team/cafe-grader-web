# Re-queue grading for submissions belonging to the "manager-affected" problems
# (those whose ev directory has a lib/ folder or a custom script/compile that
# references manager source files). Use after the reset+remigrate fix.
#
# Two modes:
#   default (MODE=baseline) — only the submissions captured in sanity_baseline.json.
#                             Fast; meant to feed sanity_compare for verification.
#   MODE=all                — every submission for the affected problems.
#                             Slower; meant for production rejudge.
#
# Run:
#   bin/rails runner script/migrate_2023/rejudge_affected.rb
#   MODE=all bin/rails runner script/migrate_2023/rejudge_affected.rb 2>&1 | tee /tmp/rejudge.log
#
# Then wait for the worker to drain and run sanity_compare.rb to read results.

require 'json'
require 'set'

EV_DIR = '/home/dae/cafe-grader/old-judge/ev'
MODE = (ENV['MODE'] || 'baseline').downcase
ASSUME_YES = ENV['YES'] == '1'

$stdout.sync = true
Rainbow.enabled = true

# Identify affected problem names from the filesystem (lib/ dir OR compile
# script that references /lib/ or /script/ source files).
affected = Set.new
Dir["#{EV_DIR}/*/lib"].each { |d| affected << File.basename(File.dirname(d)) }
Dir["#{EV_DIR}/*/script/compile"].each do |cf|
  next unless File.binread(cf) =~ %r{/judge/ev/[\w.+-]+/(?:lib|script)/[\w.+-]+\.(?:c|cpp|cc|h|hpp)}i
  affected << File.basename(File.dirname(File.dirname(cf)))
end
puts "Identified #{affected.size} affected problem names from the ev/ filesystem."

problems = Problem.where(name: affected.to_a).to_a
puts "Of those, #{problems.size} exist as Problem rows in DB."
problem_ids = problems.map(&:id)

# Build the submission scope based on MODE.
case MODE
when 'baseline'
  baseline_path = File.expand_path('sanity_baseline.json', __dir__)
  abort "Baseline not found: #{baseline_path}" unless File.exist?(baseline_path)
  data = JSON.parse(File.read(baseline_path))
  baseline_sub_ids = data['submissions'].map { |s| s['sub_id'] }
  scope = Submission.where(problem_id: problem_ids, id: baseline_sub_ids)
when 'all'
  scope = Submission.where(problem_id: problem_ids)
else
  abort "Unknown MODE=#{MODE}. Use 'baseline' or 'all'."
end

total = scope.count
by_problem = scope.group(:problem_id).count
puts ''
puts "Mode: #{MODE}"
puts "Submissions to rejudge: #{total}"
if MODE == 'all'
  puts ''
  puts 'Per-problem submission counts (top 20):'
  by_problem.sort_by { |_pid, n| -n }.first(20).each do |pid, n|
    pname = problems.find { |p| p.id == pid }&.name || "##{pid}"
    puts "  #{pname.ljust(32)} #{n}"
  end
end

if total == 0
  puts 'Nothing to rejudge.'
  exit 0
end

unless ASSUME_YES
  print Rainbow("\nThis will reset status/points for #{total} submissions and queue grade jobs. Type 'yes' to proceed: ").color(:yellow)
  abort 'aborted' unless $stdin.gets.to_s.strip == 'yes'
end

queued = 0
skipped_no_dataset = 0
errors = 0

scope.find_each do |sub|
  unless sub.problem.live_dataset
    skipped_no_dataset += 1
    next
  end
  begin
    sub.add_judge_job
    queued += 1
    print '.' if queued % 50 == 0
  rescue => e
    errors += 1
    puts "\n  ERROR queuing ##{sub.id}: #{e.class}: #{e.message[0, 80]}"
  end
end
puts ''
puts ''
puts "Queued: #{queued}"
puts "Skipped (no live_dataset): #{skipped_no_dataset}"
puts "Errors:                    #{errors}"
puts ''
puts 'Worker should now process the queue. Verify with:'
puts '  bin/rails runner "puts Job.group(:status).count.inspect"'
puts ''
puts 'Once the queue drains, classify the result:'
puts '  bin/rails runner script/migrate_2023/sanity_compare.rb'
