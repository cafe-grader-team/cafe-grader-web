# Test harness for migrate_tasks_v2.rb. Exercises one example per checker
# branch and verifies that re-running do_dir on the same problem is a no-op.
#
# Run:
#   bin/rails runner script/migrate_2023/test_v2.rb
#
# To force a clean import (destroys any existing 'default' dataset for the
# example problems before phase 1):
#   RESET=1 bin/rails runner script/migrate_2023/test_v2.rb
#
# To capture the full verbose log as well as the summary report:
#   RESET=1 bin/rails runner script/migrate_2023/test_v2.rb 2>&1 | tee /tmp/test_v2.log

# Prevent migrate_tasks_v2.rb from auto-running main() at the bottom.
MIGRATE_TASKS_V2_SKIP_AUTORUN = true
load File.expand_path('migrate_tasks_v2.rb', __dir__)

EXAMPLES = {
  '063_jun17_racing'      => '(a) text checker (default)',
  'gcj_fallingdiamonds'   => '(b) float checker (relative)',
  'oct21_bridge'          => '(c) integer checker (default)',
  '12apr19_lying'         => '(d) REAL_CHECK_SCRIPT -> binary (a.out)',
  'apr18_cluster'         => '(d) REAL_CHECK_SCRIPT -> script (check_cluster)',
  'o62_may15_mooz_server' => '(d) REAL_CHECK_SCRIPT -> MISSING (check-exam)',
  'balkan11_trapezoid'    => '(e) custom inline, variant of template',
  'croatia13_hip'         => '(e) custom inline, true outlier',
  'jun04_walk'            => '    no script/check (also no all_tests.cfg)',
}

def ensure_problem(name)
  Problem.find_or_create_by!(name: name) do |p|
    p.full_name = "test fixture: #{name}"
    p.date_added = Time.zone.now
    p.available = false
  end
end

def snapshot(problem)
  {
    datasets: problem.datasets.count,
    testcases: Testcase.where(dataset_id: problem.datasets.ids).count,
    blobs: ActiveStorage::Blob.count,
    attachments: ActiveStorage::Attachment.count,
  }
end

def short_error(e)
  msg = e.message.lines.first.to_s.strip
  msg = msg[0, 90] + '...' if msg.length > 90
  "#{e.class.name}: #{msg}"
end

results = []  # one entry per example

puts '=' * 72
puts 'TEST HARNESS for migrate_tasks_v2.rb'
puts '=' * 72
puts "EV_DIR = #{EV_DIR}"
puts "Examples: #{EXAMPLES.size}"
puts ''

# Optional reset.
if ENV['RESET'] == '1'
  puts '--- RESET: destroying existing "default" datasets for example problems ---'
  EXAMPLES.each_key do |name|
    p = Problem.where(name: name).first
    next unless p
    if p.datasets.where(name: 'default').exists?
      p.update_column(:live_dataset_id, nil)
      p.datasets.where(name: 'default').destroy_all
      puts "  reset #{name}"
    end
  end
  puts ''
end

# Pre-state listing.
puts '--- pre-state ---'
EXAMPLES.each do |name, _|
  p = Problem.where(name: name).first
  if p
    has_default = p.datasets.where(name: 'default').exists?
    puts "  #{name.ljust(28)} exists=true  default_dataset=#{has_default}"
  else
    puts "  #{name.ljust(28)} exists=false (will be created)"
  end
end

# ---- PHASE 1: first run ----
puts ''
puts '--- PHASE 1: first run of do_dir ---'
EXAMPLES.each do |name, desc|
  entry = { name: name, desc: desc, phase1: nil, phase2: nil }
  prob_dir = EV_DIR + name
  unless prob_dir.directory?
    puts "  SKIP #{name}: ev dir missing at #{prob_dir}"
    entry[:phase1] = { status: :missing_dir }
    results << entry
    next
  end
  problem = ensure_problem(name)
  puts ''
  puts "==> #{name}  #{desc}"
  begin
    do_dir(prob_dir)
    problem.reload
    ds = problem.live_dataset
    if ds.nil?
      entry[:phase1] = { status: :no_dataset }
      puts '    [after-1] live_dataset: nil'
    else
      entry[:phase1] = {
        status: :ok,
        eval_type: ds.evaluation_type,
        score_type: ds.score_type,
        time_limit: ds.time_limit,
        memory_limit: ds.memory_limit,
        testcases: ds.testcases.count,
        checker_attached: ds.checker.attached?,
        checker_filename: ds.checker.attached? ? ds.checker.filename.to_s : nil,
        checker_bytes: ds.checker.attached? ? ds.checker.byte_size : nil,
      }
      ck = ds.checker.attached? ? "#{ds.checker.filename} (#{ds.checker.byte_size}B)" : 'none'
      puts "    [after-1] eval=#{ds.evaluation_type} score=#{ds.score_type} " \
           "tl=#{ds.time_limit} ml=#{ds.memory_limit} " \
           "tcs=#{ds.testcases.count} live=#{ds.live?}"
      puts "    [after-1] checker: #{ck}"
    end
  rescue => e
    entry[:phase1] = { status: :error, error: short_error(e) }
    puts "    !!! ERROR: #{short_error(e)}"
    puts "    #{e.backtrace.first(3).join("\n    ")}"
  end
  results << entry
end

# ---- PHASE 2: re-run idempotency ----
puts ''
puts '--- PHASE 2: second run of do_dir (idempotency) ---'
results.each do |entry|
  next if entry[:phase1].nil? || entry[:phase1][:status] == :missing_dir
  name = entry[:name]
  prob_dir = EV_DIR + name
  problem = Problem.where(name: name).first
  unless problem
    entry[:phase2] = { status: :no_problem }
    next
  end

  before = snapshot(problem)
  puts ''
  puts "==> #{name}  #{entry[:desc]}"
  begin
    do_dir(prob_dir)
    problem.reload
    after = snapshot(problem)
    diff = after.each_with_object({}) { |(k, v), h| h[k] = v - before[k] if v != before[k] }
    if diff.empty?
      entry[:phase2] = { status: :ok }
      puts "    OK: no changes (#{before.inspect})"
    else
      entry[:phase2] = { status: :violation, diff: diff }
      puts "    !!! VIOLATION: #{diff.inspect}"
    end
  rescue => e
    entry[:phase2] = { status: :error, error: short_error(e) }
    puts "    !!! ERROR: #{short_error(e)}"
  end
end

# ---- SUMMARY ----
summary_lines = []
summary_lines << ''
summary_lines << '=' * 72
summary_lines << 'SUMMARY'
summary_lines << '=' * 72
fmt = "%-28s | %-32s | %-30s"
summary_lines << format(fmt, 'problem', 'phase1', 'phase2')
summary_lines << format(fmt, '-' * 28, '-' * 32, '-' * 30)

phase1_counts = Hash.new(0)
phase2_counts = Hash.new(0)

results.each do |r|
  p1 = r[:phase1] || {}
  p2 = r[:phase2] || {}
  phase1_counts[p1[:status]] += 1
  phase2_counts[p2[:status] || :not_run] += 1

  p1_label = case p1[:status]
             when :ok          then "ok eval=#{p1[:eval_type]} tcs=#{p1[:testcases]}"
             when :missing_dir then 'missing_dir'
             when :no_dataset  then 'no_dataset'
             when :error       then "ERROR: #{p1[:error]}"
             else '-'
             end
  p2_label = case p2[:status]
             when :ok        then 'idempotent'
             when :violation then "VIOLATION #{p2[:diff].inspect}"
             when :error     then "ERROR: #{p2[:error]}"
             when :no_problem then 'no_problem'
             else '(not run)'
             end
  summary_lines << format(fmt, r[:name], p1_label[0, 32], p2_label[0, 30])
end

summary_lines << ''
summary_lines << "phase 1 totals: #{phase1_counts.inspect}"
summary_lines << "phase 2 totals: #{phase2_counts.inspect}"
summary_lines << ''
overall = if phase1_counts.except(:ok).empty? && phase2_counts.except(:ok, :not_run).empty?
            'OVERALL: PASS'
          else
            'OVERALL: FAIL (see entries above)'
          end
summary_lines << overall
summary_lines << '=' * 72

summary_text = summary_lines.join("\n")
puts summary_text

# Save report.
report_dir = File.expand_path(__dir__)
report_path = File.join(report_dir, "test_v2_report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
File.write(report_path, summary_text + "\n")
puts ''
puts "Summary report saved to: #{report_path}"
