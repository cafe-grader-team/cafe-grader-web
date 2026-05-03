# Fixed version of migrate_tasks.rb. Differences from the original:
#   * Source paths are configured via the constants block below; main() prints the
#     resolved paths and asks for explicit confirmation before doing anything.
#   * read_managers_from_ev disables do_solutions / do_attachment / do_initializers
#     (the importer's defaults grew since this script was written and would otherwise
#      create stray Submission rows, attach random files as the public attachment, etc.)
#   * do_dir skips problems whose Problem already has a 'default' dataset, so re-runs
#     don't pile up orphan datasets and don't clobber any post-migration edits.
#   * read_checker_from_ev:
#       - REAL_CHECK_SCRIPT branch uses binread, classifies the target as
#         binary / script / unknown, and handles a missing target gracefully
#         (logs an error, leaves no checker attached, continues the run).
#       - Custom-inline branch logs the closest matching template plus line-overlap
#         ratio when > 50%, so near-variants of the stock checkers are discoverable
#         post-migration. Behavior is unchanged: still attached as 'custom_cafe'.
#   * main() PDF attachment skips problems whose statement is already attached,
#     so re-runs do not orphan blobs.
#   * main() submission rescale runs per-problem and sets full_score = 100 as a
#     sentinel; re-runs are then no-ops. The original script could double-rescale
#     and corrupt data on a second run.
#   * The bottom-of-file invocation respects MIGRATE_TASKS_V2_SKIP_AUTORUN so test
#     harnesses can `load` the file without triggering the migration.
#   * parse_all_test_cfg only writes ds.memory_limit / ds.time_limit when the
#     corresponding cfg line was actually parsed (was unconditional, would set
#     to nil for cfgs missing those lines).
#   * read_managers_from_ev accepts memory_limit / time_limit kwargs, forwarded
#     to ProblemImporter, and do_dir passes through the cfg-parsed values.
#     Without this, the importer's own defaults (512 MB / 1 s) silently
#     clobbered whatever parse_all_test_cfg had set, so every migrated problem
#     ended up with memory_limit = 512 regardless of its legacy setting.
#
# Original migration overview:
#   For each <EV_DIR>/<problem-name> directory matching a Problem.name:
#     1. import each testcase into a new 'default' Dataset (becomes live_dataset)
#     2. parse all_tests.cfg for time/memory limits and group/score settings
#     3. read managers via ProblemImporter
#     4. classify and attach the checker
#   Then attach pre-existing PDFs from TASK_PDF_DIR/<id>/<filename>, reseed Languages,
#   clear GraderProcess, and rescale legacy points to a 0-100 scale.
#
# If migrating from pre-2023, you may need to drop these tables first:
#   drop table active_storage_attachments, active_storage_variant_records,
#              active_storage_blobs, jobs, datasets, evaluations, worker_datasets;

# === MIGRATION SOURCE PATHS =================================================
# Edit these to match your machine before running.
LEGACY_JUDGE_DIR  = Pathname.new('/home/dae/cafe-grader/old-judge')
EV_DIR            = LEGACY_JUDGE_DIR + 'ev'
JUDGE_SCRIPTS_DIR = LEGACY_JUDGE_DIR + 'scripts'
TASK_PDF_DIR      = Rails.root.join('data', 'tasks')
# ============================================================================

# Force unbuffered stdout so progress and the confirmation prompt are visible
# when piped through tee. Without this, Ruby block-buffers when stdout isn't a
# TTY and the script appears hung at the `gets` prompt.
$stdout.sync = true

# Rainbow disables color when stdout isn't a TTY (so log files stay clean), but
# we typically run this through `tee /tmp/...log` and want the terminal colored.
# Force-enable. View the log with `less -R` to render the ANSI escapes.
Rainbow.enabled = true

# Anomaly log: per-problem warnings (missing testcase files, repaired orphan
# datasets, REAL_CHECK_SCRIPT pointing at missing targets, etc.) are appended
# here AND printed in red on the terminal. Path is printed again at end of run.
ANOMALY_LOG_PATH = File.expand_path('migrate_anomalies.log', __dir__)

# Counters populated as the run progresses. Printed by print_summary at the end.
STATS = Hash.new(0)
START_TIME = Time.now

def log_anomaly(kind, **fields)
  STATS[:anomalies] += 1
  STATS[:"anomaly_#{kind}"] += 1
  parts = fields.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')
  entry = "[#{Time.zone.now.iso8601}] #{kind} #{parts}"
  puts Rainbow("ANOMALY: #{entry}").color(:red)
  File.open(ANOMALY_LOG_PATH, 'a') { |f| f.puts(entry) }
end

def confirm_or_exit
  puts '=' * 64
  puts 'CAFE-GRADER LEGACY MIGRATION (migrate_tasks_v2.rb)'
  puts '=' * 64
  puts "  Legacy judge dir:   #{LEGACY_JUDGE_DIR}"
  puts "  EV dir (problems):  #{EV_DIR}"
  puts "  Judge scripts dir:  #{JUDGE_SCRIPTS_DIR}"
  puts "  Task PDF dir:       #{TASK_PDF_DIR}"
  puts ''

  unless EV_DIR.directory?
    puts "ERROR: EV_DIR does not exist or is not a directory: #{EV_DIR}"
    puts 'Edit the constants block at the top of this script and re-run.'
    exit 1
  end
  unless JUDGE_SCRIPTS_DIR.directory?
    puts "WARNING: JUDGE_SCRIPTS_DIR does not exist: #{JUDGE_SCRIPTS_DIR}"
    puts 'Default-checker template comparison will fail. Continue anyway? '
  end

  problem_count = Dir["#{EV_DIR}/*"].count { |p| File.directory?(p) }
  puts "  Found #{problem_count} problem directories under EV_DIR."
  puts ''
  puts 'This migration will:'
  puts '  - Create new "default" datasets for matching Problems and attach test cases'
  puts '  - Reseed Languages, clear GraderProcess, rescale Submission.points'
  puts '  - Skip Problems that already have a "default" dataset'
  puts ''
  print 'Proceed? Type "yes" to continue, anything else aborts: '
  ans = $stdin.gets.to_s.strip
  unless ans == 'yes'
    puts 'Aborted.'
    exit 0
  end
  puts ''
end

def import_all_testcase(prob_ev_dir,problem)
  ds = Dataset.create(problem: problem,name: 'default')

  testcases_root = prob_ev_dir + 'test_cases'
  num = 1
  loop do
    file_root = testcases_root + "#{num}"
    break unless File.exist? file_root

    inp_path = file_root + "input-#{num}.txt"
    ans_path = file_root + "answer-#{num}.txt"
    unless inp_path.exist? && ans_path.exist?
      log_anomaly('missing_testcase_file',
                  problem: problem.name,
                  num: num,
                  has_input: inp_path.exist?,
                  has_answer: ans_path.exist?,
                  dir: file_root.to_s)
      num += 1
      next
    end

    # binread, not read: testcase files can contain non-UTF-8 bytes (binary
    # inputs, Latin-1 text), and File.read tags them as UTF-8 which then
    # crashes gsub on invalid byte sequences. binread returns ASCII-8BIT.
    inp = File.binread(inp_path).gsub(/\r$/, '')
    ans = File.binread(ans_path).gsub(/\r$/, '')
    puts "  got test case ##{num} of size #{inp.size} and #{ans.size}"

    tc = Testcase.create(num: num,code_name: num, weight: 10,group: num,dataset: ds)
    tc.inp_file.attach(io: StringIO.new(inp), filename: 'input.txt', content_type: 'text/plain',  identify: false)
    tc.ans_file.attach(io: StringIO.new(ans), filename: 'answer.txt', content_type: 'text/plain',  identify: false)
    tc.save
    STATS[:testcases_imported] += 1
    num += 1
  end
  # NOTE: problem.live_dataset is finalized at the END of do_dir, only after
  # cfg/managers/checker steps all succeed. If anything below crashes, the
  # dataset stays orphaned (live_dataset_id != ds.id) so the orphan detector
  # in do_dir will rebuild it on the next run.
  return ds
end

# read all_test cfg file and return a hash information
def parse_all_test_cfg(filename,ds)
  unless File.exist?(filename)
    puts "  no all_tests.cfg at #{filename}, leaving dataset defaults"
    return {}
  end
  on_run = false
  run = nil
  tests = nil
  scores = nil
  result = {}
  File.foreach(filename).each do |line|
    #time limit
    md = /time_limit_each\s+(\d+\.?\d*)/.match line
    result[:time_limit] = md[1].to_f if md

    # mem limit
    md = /mem_limit_each\s+(\d+\.?\d*)/.match line
    result[:mem_limit] = md[1].to_f if md

    # score_each
    md = /score_each\s+(\d+\.?\d*)/.match line
    result[:score_each] = md[1].to_f if md

    #run detect
    md = /run\s+(\d+)\s+do/.match line
    if (md && !on_run)
      run = md[1].to_i
      on_run = true
      tests = nil
      scores = nil
    end

    #test on run
    md = /tests\s+([\d,\s]*)/.match line
    if (md && on_run)
      tests = md[1].split(',').map { |x| x.to_i}
    end

    #score on run
    md = /scores\s+([\d,\s]*)/.match line
    if (md && on_run)
      scores = md[1].split(',').map { |x| x.to_i}
    end

    md = /end/.match line
    if (md && on_run)
      result[:group] = true if tests && tests.count > 1
      on_run = false
      result[run] = {tests: tests,scores: scores, errors: []}
      result[run][:errors] << "no test" unless tests
      result[run][:errors] << "no scores" unless scores

      if tests && scores && !scores.empty?
        tests.each do |num|
          ds.testcases.where(num: num).update(group: run, weight: scores[0], group_name: 'group '+run.to_s)
        end
      else
        # Malformed run block (missing tests or scores). The original script
        # raised here on scores[0]; we log and let the affected testcases keep
        # their import-time defaults (weight=10, per-num group).
        log_anomaly('cfg_run_block_incomplete',
                    problem: ds.problem.name,
                    run: run,
                    tests: tests,
                    scores: scores)
      end
    end
  end
  ds.memory_limit = result[:mem_limit] if result[:mem_limit]
  ds.time_limit   = result[:time_limit] if result[:time_limit]
  ds.score_type = 'group_min' if result[:group]
  ds.save
  return result
end

# memory_limit / time_limit are forwarded to ProblemImporter so that values
# previously set on `ds` (e.g. by parse_all_test_cfg) are not clobbered by the
# importer's own defaults. The importer unconditionally writes
# @dataset.memory_limit = memory_limit, so we have to pass the right value.
def read_managers_from_ev(prob_ev_dir, ds, memory_limit: 512, time_limit: 1)
  pi = ProblemImporter.new
  pi.import_dataset_from_dir(prob_ev_dir,ds.problem.name,
                             full_name: ds.problem.full_name,
                             dataset: ds,
                             do_testcase: false,
                             do_statement: false,
                             do_checker: false,
                             do_solutions: false,
                             do_attachment: false,
                             do_initializers: false,
                             memory_limit: memory_limit,
                             time_limit: time_limit,
                            )
  pp pi.log if pi.got.count > 0

  attach_managers_from_compile(prob_ev_dir, ds)
end

# Parse the legacy script/compile for references to source/header files in the
# problem's own subdirectories. The legacy convention puts manager code in
# either lib/ (most problems) or script/ (a handful), and the compile command
# is the source of truth for which files are linked alongside the student
# submission.
#
# Returns:
#   { source_refs: { 'lib' => ['grader.cpp'], ... },
#     include_subdirs: ['lib', 'script'] }
def parse_compile_refs(prob_ev_dir)
  compile_path = prob_ev_dir + 'script' + 'compile'
  return { source_refs: {}, include_subdirs: [] } unless compile_path.exist?
  content = File.binread(compile_path)

  # /judge/ev/<problem>/<subdir>/<filename.ext>
  matches = content.scan(%r{/judge/ev/[\w.+-]+/(\w+)/([\w.+-]+\.(?:c|cpp|cc|h|hpp))}i)
  source_refs = Hash.new { |h, k| h[k] = [] }
  matches.each { |sub, fn| source_refs[sub] << fn }
  source_refs.each_value(&:uniq!)

  include_subdirs = content.scan(%r{-I\s*/judge/ev/[\w.+-]+/(\w+)/?}i).flatten.uniq

  { source_refs: source_refs, include_subdirs: include_subdirs }
end

# Attach helper files from the problem's manager subdirectories (lib/ or script/
# or whatever the compile script references) and override main_filename when
# the compile script names a non-standard main (e.g. pandemic uses
# pandelib_private.cpp; ProblemImporter only looks for grader.cpp/main.cpp/
# main_grader.cpp).
#
# Decisions:
#   * Manager subdir(s) come from script/compile (any path matching
#     /judge/ev/<name>/<subdir>/<file>). Falls back to lib/ if it exists and
#     the compile script doesn't reference any subdir.
#   * Within each manager subdir:
#     - .h / .hpp / .hxx / .hh files are attached (they're on the include path).
#     - .c / .cpp / .cc files are attached only if listed in the compile script
#       (avoids attaching stale model code that isn't linked).
#   * Backups (~, .bak, .org, .mod\d*) and ELF binaries (filtered by extension)
#     are skipped.
#   * Files sharing a basename stem with the REAL_CHECK_SCRIPT target are
#     skipped (those are checker source, not student-side).
#   * main_filename is set/overridden to the compile-referenced .cpp (or .c).
def attach_managers_from_compile(prob_ev_dir, ds)
  parsed = parse_compile_refs(prob_ev_dir)
  source_refs = parsed[:source_refs]
  include_subdirs = parsed[:include_subdirs]

  source_dirs = (source_refs.keys + include_subdirs).uniq
  if source_dirs.empty? && (prob_ev_dir + 'lib').directory?
    source_dirs = ['lib']    # backwards-compat for problems with lib/ but no compile-script ref
  end
  return if source_dirs.empty?

  ds.reload
  existing = ds.managers.map { |m| m.filename.to_s }

  checker_stem = nil
  check_file = prob_ev_dir + 'script' + 'check'
  if check_file.exist?
    md = /REAL_CHECK_SCRIPT = "(.*)"/.match(File.binread(check_file))
    checker_stem = File.basename(md[1], '.*') if md
  end

  attached = []
  source_dirs.each do |subdir|
    dir = prob_ev_dir + subdir
    next unless dir.directory?
    refs_in_dir = source_refs[subdir] || []

    Dir["#{dir}/*"].sort.each do |fn|
      pn = Pathname.new(fn)
      next unless pn.file?
      basename = pn.basename.to_s
      ext = pn.extname

      next unless %w[.h .hpp .hxx .hh .c .cpp .cc].include?(ext)
      next if basename.match?(/(~|\.bak|\.org|\.mod\d*)$/)
      next if existing.include?(basename)
      next if checker_stem && File.basename(basename, '.*') == checker_stem

      is_header = %w[.h .hpp .hxx .hh].include?(ext)
      is_compile_ref = refs_in_dir.include?(basename)
      next unless is_header || is_compile_ref

      ds.managers.attach(io: File.open(pn), filename: basename)
      existing << basename
      attached << "#{subdir}/#{basename}"
    end
  end

  all_refs = source_refs.values.flatten
  inferred_main = all_refs.find { |f| f.end_with?('.cpp', '.cc') } ||
                  all_refs.find { |f| f.end_with?('.c') }
  if inferred_main && ds.main_filename != inferred_main
    if ds.main_filename.present?
      puts "  override main_filename: '#{ds.main_filename}' -> '#{inferred_main}' (from compile script)"
    else
      puts "  set main_filename = '#{inferred_main}' (from compile script)"
    end
    ds.update_columns(main_filename: inferred_main)
    problem_updates = { compilation_type: 'with_managers' }
    problem_updates[:submission_filename] = 'student.h' if ds.problem.submission_filename.blank?
    ds.problem.update(problem_updates)
    STATS[:lib_main_filename_set] += 1
  end

  if attached.any?
    STATS[:lib_managers_attached] += attached.size
    puts "  attached managers: #{attached.join(', ')}"
  end
end

def read_default_checker(judge_script_dir = JUDGE_SCRIPTS_DIR)
  return unless @default_checker_text.nil?
  # binread for byte-level consistency with how we read per-problem checkers,
  # so == comparison doesn't get tripped up by encoding mismatches.
  @default_checker_text  = File.binread(judge_script_dir + 'templates' + 'check.text').gsub(/\r$/, '')
  @default_checker_float = File.binread(judge_script_dir + 'templates' + 'check.float').gsub(/\r$/, '')
  @default_checker_int   = File.binread(judge_script_dir + 'templates' + 'check.integer').gsub(/\r$/, '')
end

def cmp_default_checker(prob_checker, default_checker)
  return true if default_checker == prob_checker
  return true if default_checker == prob_checker.gsub('#!/usr/bin/ruby','#!/usr/bin/env ruby')
  return false
end

# Returns {name: :text/:float/:integer, ratio: 0.0..1.0} for the closest template,
# using normalized line-set overlap. Used only for logging near-variants.
def closest_template_similarity(prob_checker)
  read_default_checker
  templates = {
    text:    @default_checker_text,
    float:   @default_checker_float,
    integer: @default_checker_int,
  }
  prob_lines = prob_checker.gsub('#!/usr/bin/ruby', '#!/usr/bin/env ruby').lines
  scored = templates.map do |name, body|
    tpl_lines = body.lines
    common = (prob_lines & tpl_lines).size
    denom = [prob_lines.size, tpl_lines.size].max
    ratio = denom.zero? ? 0.0 : common.to_f / denom
    { name: name, ratio: ratio }
  end
  scored.max_by { |s| s[:ratio] }
end

# Classify a checker target file by its first few bytes.
# Returns one of :binary, :script, :unknown.
def classify_checker_target(bytes)
  return :binary if bytes.start_with?("\x7FELF".b)
  return :script if bytes.start_with?('#!')
  :unknown
end

def read_checker_from_ev(prob_ev_dir,ds)
  read_default_checker
  check_file = prob_ev_dir + 'script' + 'check'
  unless check_file.exist?
    STATS[:checker_none] += 1
    puts "skipping #{prob_ev_dir} because no check"
    return
  end
  my_checker = File.binread(check_file).gsub(/\r$/, '')
  prob_name = prob_ev_dir

  md = /REAL_CHECK_SCRIPT = "(.*)"/.match(my_checker)

  if cmp_default_checker(my_checker , @default_checker_text)
    STATS[:checker_text] += 1
    ds.evaluation_type = 'default'
    puts "Problem #{prob_name} has " + Rainbow("text checker").color(:deeppink)
  elsif cmp_default_checker(my_checker , @default_checker_float)
    STATS[:checker_float] += 1
    ds.evaluation_type = 'relative'
    puts "Problem #{prob_name} has " + Rainbow("float checker").color(:seagreen)
  elsif cmp_default_checker(my_checker , @default_checker_int)
    STATS[:checker_integer] += 1
    ds.evaluation_type = 'default'
    puts "Problem #{prob_name} has " + Rainbow("int checker").color(:orange)
  elsif md
    ds.evaluation_type = 'custom_cafe'
    target_path = check_file.dirname + md[1]
    if !target_path.exist?
      STATS[:checker_cms_missing] += 1
      log_anomaly('real_check_script_missing',
                  problem: ds.problem.name,
                  target: md[1].to_s,
                  expected_path: target_path.to_s)
      puts "Problem #{prob_name} has " + Rainbow("REAL_CHECK_SCRIPT pointing at MISSING file '#{md[1]}' (no checker attached)").color(:red)
    else
      bytes = target_path.binread
      kind = classify_checker_target(bytes)
      STATS[:"checker_cms_#{kind}"] += 1
      ds.checker.attach(io: StringIO.new(bytes), filename: md[1], content_type: 'application/octet-stream')
      puts "Problem #{prob_name} has " + Rainbow("CUSTOM CMS checker [#{kind}: #{md[1]}]").color(:skyblue)
    end
  else
    ds.evaluation_type = 'custom_cafe'
    ds.checker.attach(io: StringIO.new(my_checker), filename: 'checker', content_type: 'application/octet-stream')
    closest = closest_template_similarity(my_checker)
    if closest && closest[:ratio] > 0.5
      STATS[:checker_custom_variant] += 1
      pct = (closest[:ratio] * 100).round
      puts "Problem #{prob_name} has " + Rainbow("CUSTOM checker (variant of #{closest[:name]}, #{pct}% line-overlap -- review)").color(:gold)
    else
      STATS[:checker_custom_outlier] += 1
      puts "Problem #{prob_name} has " + Rainbow("CUSTOM checker").color(:skyblue)
    end
  end

  ds.save
end


def do_dir(prob_ev_dir)
  STATS[:ev_dirs_seen] += 1

  p = Problem.where(name: prob_ev_dir.basename.to_s).first
  unless p
    STATS[:no_problem_in_db] += 1
    puts "cannot find Problem with name #{prob_ev_dir.basename.to_s}"
    return
  end

  default_ds = p.datasets.where(name: 'default').first
  if default_ds
    if p.live_dataset_id == default_ds.id
      # Successful previous import: import_all_testcase sets live_dataset only
      # at the very end, so a matching live_dataset means the loop completed.
      STATS[:skipped_complete] += 1
      puts "skipping #{prob_ev_dir.basename}: 'default' already imported for problem ##{p.id} (#{default_ds.testcases.count} testcases)"
      return
    else
      # Crashed-mid-import orphan: dataset row exists, but live_dataset never
      # got pointed at it. Destroy and re-import.
      STATS[:repaired_orphan] += 1
      log_anomaly('repairing_orphan_dataset',
                  problem: p.name,
                  dataset_id: default_ds.id,
                  testcase_count: default_ds.testcases.count)
      puts Rainbow("REPAIRING #{prob_ev_dir.basename}: previous run left orphan dataset ##{default_ds.id} (#{default_ds.testcases.count} testcases). Destroying and re-importing.").color(:gold)
      default_ds.destroy
      p.reload
    end
  end

  # import all testcases in ev/{prob}/test_cases/xxx into a new live dataset ds
  ds = import_all_testcase(prob_ev_dir,p)

  r = parse_all_test_cfg(prob_ev_dir + 'test_cases/all_tests.cfg',ds)
  puts "Problem #{p.name} (#{p.id}) has grouped testcase" if (r[:group])

  # read manager. Forward the cfg-parsed limits so the importer doesn't reset
  # them to its defaults; fall back to 512 / 1 only when cfg supplied nothing.
  read_managers_from_ev(prob_ev_dir, ds,
                        memory_limit: ds.memory_limit || 512,
                        time_limit: ds.time_limit || 1)

  # read checker
  read_checker_from_ev(prob_ev_dir,ds)

  # Finalize: set live_dataset only now, after all import steps succeeded.
  # See note in import_all_testcase for why.
  p.live_dataset = ds
  p.save
  STATS[:imported_fresh] += 1
end

def main
  confirm_or_exit

  # re-import testcases and checker and managers as new Dataset
  Dir["#{EV_DIR}/*"].each do |ev_dir|
    prob_ev_dir = Pathname.new ev_dir
    do_dir(prob_ev_dir)
  end

  # import pdf (skip if already attached so re-runs don't orphan blobs)
  Problem.where.not(description_filename: nil).each do |p|
    next if p.statement.attached?
    file = TASK_PDF_DIR + p.id.to_s + p.description_filename
    if file.exist?
      p.statement.attach(io: File.open(file), filename: p.description_filename)
      STATS[:pdfs_attached] += 1
      puts "found pdf for #{p.name} at #{file.basename}"
    end
  end

  # re-seed language
  Language.seed

  # clear grader process
  GraderProcess.delete_all

  # Rescale legacy per-problem points to a 0-100 scale, then mark each problem
  # by setting full_score = 100. The 'full_score != 100' filter makes re-runs
  # a no-op (without it, repeated runs would divide the points again).
  Problem.where('full_score > 1 AND full_score != 100').find_each do |prob|
    affected = Submission.where(problem_id: prob.id)
                         .update_all("points = points / #{prob.full_score.to_i} * 100")
    prob.update_column(:full_score, 100)
    STATS[:rescaled_problems] += 1
    STATS[:rescaled_submissions] += affected
    puts "rescaled #{affected} submissions for problem #{prob.name} (##{prob.id})"
  end
  puts "DONE"
  print_summary
end

def print_summary
  elapsed = Time.now - START_TIME
  puts ''
  puts '=' * 64
  puts Rainbow('MIGRATION SUMMARY').color(:cyan)
  puts '=' * 64
  puts format("  elapsed: %dm %ds", (elapsed / 60).to_i, (elapsed % 60).to_i)
  puts ''
  puts "  ev directories scanned:    #{STATS[:ev_dirs_seen]}"
  puts "    no Problem row in DB:    #{STATS[:no_problem_in_db]}"
  puts "    already imported (skip): #{STATS[:skipped_complete]}"
  puts "    repaired (orphan):       #{STATS[:repaired_orphan]}"
  puts "    freshly imported:        #{STATS[:imported_fresh]}"
  puts "  testcases imported (run):  #{STATS[:testcases_imported]}"
  puts ''
  puts "  checker classification (this run only):"
  puts "    text  (default):         #{STATS[:checker_text]}"
  puts "    float (relative):        #{STATS[:checker_float]}"
  puts "    int   (default):         #{STATS[:checker_integer]}"
  puts "    REAL_CHECK_SCRIPT bin:   #{STATS[:checker_cms_binary]}"
  puts "    REAL_CHECK_SCRIPT scr:   #{STATS[:checker_cms_script]}"
  puts "    REAL_CHECK_SCRIPT ?:     #{STATS[:checker_cms_unknown]}"
  puts "    REAL_CHECK_SCRIPT miss:  #{STATS[:checker_cms_missing]}"
  puts "    custom (template var):   #{STATS[:checker_custom_variant]}"
  puts "    custom (outlier):        #{STATS[:checker_custom_outlier]}"
  puts "    no script/check:         #{STATS[:checker_none]}"
  puts ''
  puts "  lib/ managers attached:    #{STATS[:lib_managers_attached]}"
  puts "  main_filename set/changed: #{STATS[:lib_main_filename_set]}"
  puts "  PDF statements attached:   #{STATS[:pdfs_attached]}"
  puts "  problems rescaled:         #{STATS[:rescaled_problems]}"
  puts "  submissions rescaled:      #{STATS[:rescaled_submissions]}"
  puts ''
  if STATS[:anomalies] > 0
    puts Rainbow("  anomalies logged: #{STATS[:anomalies]}").color(:red)
    STATS.keys.grep(/^anomaly_/).sort.each do |k|
      kind = k.to_s.sub(/^anomaly_/, '')
      puts "    #{kind.ljust(28)} #{STATS[k]}"
    end
    puts "  log file: #{ANOMALY_LOG_PATH}"
  else
    puts "  anomalies logged: 0"
  end
  puts '=' * 64
end

def tmp_test
  Dir["#{EV_DIR}/*"].each do |ev_dir|
    prob_ev_dir = Pathname.new ev_dir
    p = Problem.where(name: prob_ev_dir.basename.to_s).first
    next unless p
    read_checker_from_ev(prob_ev_dir,p.live_dataset)
  end
end

# This runs the main migration. Test harnesses can suppress this by defining
# MIGRATE_TASKS_V2_SKIP_AUTORUN = true before `load`-ing this file.
main unless defined?(MIGRATE_TASKS_V2_SKIP_AUTORUN) && MIGRATE_TASKS_V2_SKIP_AUTORUN
