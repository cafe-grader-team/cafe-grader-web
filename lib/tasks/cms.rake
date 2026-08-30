# CMS -> cafe task clone. Spec: docs/superpowers/specs/2026-08-02-cms-clone-import-design.md
# Connection settings: config/cms_remote.yml (NOT committed; see the .sample)
# or ENV CMS_SSH_HOST / CMS_REMOTE_PYTHON.

# Shared helpers for cms:clone and cms:clone_all -- kept out of the task
# blocks (Rake's DSL makes `def` inside `namespace do ... end` awkward) so
# neither task duplicates the config/validation/extract-convert-import logic.
module CmsClone
  # Result of one clone attempt. stage is nil on success, else :extract /
  # :convert / :import -- used by cms:clone_all to label REJECTED vs FAILED.
  CloneResult = Struct.new(:ok, :stage, :error, :problem, :dataset_count, :testcase_count, keyword_init: true)

  # Small read-only python snippet, streamed the same way as extract_task.py
  # (`sudo -n -u cms <python> -`). Prints one task name per line for every
  # task whose ACTIVE dataset is exactly what today's converter accepts:
  # Batch + (GroupMin|Sum). Optionally reuses/creates the same DUMP_DIR
  # extract_task.py understands, so cms:clone_all[ALL] costs only one dump
  # for the whole run (list + every clone).
  LIST_TASKS_PY = <<~'PY'
    import json, os, subprocess, sys, tempfile, shutil

    def log(msg):
        sys.stderr.write(msg + "\n")
        sys.stderr.flush()

    dump_dir_arg = sys.argv[1] if len(sys.argv) > 1 else None
    venv = os.environ.get("CMS_VENV", os.path.dirname(os.path.dirname(sys.executable)))
    cleanup = None

    if dump_dir_arg:
        dump_dir = os.path.join(dump_dir_arg, "dump")
        if os.path.exists(os.path.join(dump_dir, "contest.json")):
            log("[list] reusing existing dump at %s" % dump_dir)
        else:
            if not os.path.isdir(dump_dir_arg):
                os.makedirs(dump_dir_arg)
                os.chmod(dump_dir_arg, 0o700)
            log("[list] official cmsDumpExporter (structure only, no submissions) ...")
            subprocess.run([os.path.join(venv, "bin", "cmsDumpExporter"),
                             "-F", "-S", "-U", "-P", dump_dir],
                            check=True, stdout=sys.stderr, stderr=sys.stderr)
    else:
        cleanup = tempfile.mkdtemp(prefix="cms_list_")
        os.chmod(cleanup, 0o700)
        dump_dir = os.path.join(cleanup, "dump")
        log("[list] official cmsDumpExporter (structure only, no submissions) ...")
        subprocess.run([os.path.join(venv, "bin", "cmsDumpExporter"),
                         "-F", "-S", "-U", "-P", dump_dir],
                        check=True, stdout=sys.stderr, stderr=sys.stderr)

    try:
        with open(os.path.join(dump_dir, "contest.json")) as f:
            dump = json.load(f)
        objects = dict((k, v) for k, v in dump.items() if not k.startswith("_"))
        names = []
        for obj in objects.values():
            if obj.get("_class") != "Task":
                continue
            ds = objects.get(str(obj.get("active_dataset")))
            if not ds:
                continue
            if ds.get("task_type") == "Batch" and ds.get("score_type") in ("GroupMin", "Sum"):
                names.append(obj["name"])
        for n in sorted(names):
            print(n)
    finally:
        if cleanup:
            shutil.rmtree(cleanup, ignore_errors=True)
  PY

  def self.valid_name?(name)
    name.to_s.match?(/\A[\w.\-]+\z/)
  end

  # => [host, python] from config/cms_remote.yml + ENV overrides (ENV wins).
  def self.resolve_settings
    cfg_file = Rails.root.join('config', 'cms_remote.yml')
    cfg = File.exist?(cfg_file) ? YAML.safe_load(File.read(cfg_file), symbolize_names: true) : {}
    host   = ENV['CMS_SSH_HOST'] || cfg[:host]
    python = ENV['CMS_REMOTE_PYTHON'] || cfg[:python] || '/home/cms/cms_venv/bin/python3'
    [host, python]
  end

  # Extract + convert + import ONE task. Never raises for expected failure
  # stages (ssh/extract, conversion reject, import error) -- those come back
  # as CloneResult(ok: false); callers decide whether to abort (cms:clone) or
  # log-and-continue (cms:clone_all). Unexpected exceptions (e.g. a raised
  # ActiveRecord error) are left to propagate -- callers that need isolation
  # wrap the call themselves.
  def self.clone_task(name:, host:, python:, script:, tmp:, dump_dir: nil)
    tar_path = File.join(tmp, 'bundle.tar')
    cmd = ['ssh', '-o', 'BatchMode=yes', host, 'sudo', '-n', '-u', 'cms', python, '-', name]
    cmd << dump_dir if dump_dir
    status = nil
    File.open(tar_path, 'wb') do |out|
      Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
        stdin.write(File.read(script))
        stdin.close
        err_thread = Thread.new { stderr.each_line { |l| warn "  [cms] #{l.chomp}" } }
        IO.copy_stream(stdout, out)
        err_thread.join
        status = wait.value
      end
    end
    unless status&.success?
      return CloneResult.new(ok: false, stage: :extract, error: 'Extraction failed (see [cms] lines above).')
    end

    # Pre-scan the archive before extracting: every member must live under
    # bundle/ with safe path components (no . or .. segments, no absolute
    # paths), so a hostile/buggy bundle can't escape the tmp staging dir.
    members, st = Open3.capture2('tar', '-tf', tar_path)
    return CloneResult.new(ok: false, stage: :extract, error: 'bundle tar failed listing') unless st.success?
    members.each_line do |line|
      line = line.chomp
      next if line.empty?
      segments = line.chomp('/').split('/')
      unless line.match?(%r{\Abundle(/[\w.\-]+)*/?\z}) && segments.none? { |s| s == '.' || s == '..' }
        return CloneResult.new(ok: false, stage: :extract, error: "bundle tar contains unsafe member: #{line}")
      end
    end

    unless system('tar', '-xf', tar_path, '-C', tmp)
      return CloneResult.new(ok: false, stage: :extract, error: 'could not untar bundle')
    end
    bundle_dir = File.join(tmp, 'bundle')
    staging = File.join(tmp, 'staging')

    conv = Converters::CmsDumpConverter.new
    res = conv.convert(bundle_dir, staging)
    res[:log].each      { |l| puts "  #{l}" }
    res[:warnings].each { |w| puts "  WARNING: #{w}" }
    if res[:errors].any?
      res[:errors].each { |e| warn "  ERROR: #{e}" }
      return CloneResult.new(ok: false, stage: :convert,
                              error: "Conversion rejected the task; nothing was imported. (#{res[:errors].join('; ')})")
    end

    meta = conv.problem_meta
    pi = ProblemImporter.new
    import_log = pi.import_dataset_from_dir(staging, meta[:name], full_name: meta[:full_name])
    puts(import_log.is_a?(Array) ? import_log.map { |l| "  #{l}" }.join("\n") : "  #{import_log}")
    if pi.errors.any?
      return CloneResult.new(ok: false, stage: :import, error: "Import errors: #{pi.errors.join('; ')}")
    end

    # Carry the CMS dataset name onto the live dataset (importer auto-names it).
    if meta[:live_dataset_name].present? && pi.dataset
      target = meta[:live_dataset_name]
      sibling_names = pi.problem.datasets.where.not(id: pi.dataset.id).pluck(:name)
      if sibling_names.include?(target)
        n = 2
        candidate = "#{target}-#{n}"
        while sibling_names.include?(candidate)
          n += 1
          candidate = "#{target}-#{n}"
        end
        puts "NOTE: dataset name '#{target}' already used by another dataset of this problem; " \
             "renamed to '#{candidate}'."
        target = candidate
      end
      pi.dataset.update!(name: target)
    end

    CloneResult.new(ok: true, problem: pi.problem, dataset_count: pi.problem.datasets.count,
                     testcase_count: pi.dataset&.testcases&.count)
  end

  # Read-only survey over ssh: every task name whose active dataset the
  # converter would accept (Batch + GroupMin/Sum). dump_dir, when given, is
  # the same reusable path passed to clone_task -- the survey either creates
  # the dump (first call of the run) or reuses it.
  def self.list_importable_tasks(host:, python:, dump_dir: nil)
    cmd = ['ssh', '-o', 'BatchMode=yes', host, 'sudo', '-n', '-u', 'cms', python, '-']
    cmd << dump_dir if dump_dir
    out = nil
    status = nil
    Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
      stdin.write(LIST_TASKS_PY)
      stdin.close
      err_thread = Thread.new { stderr.each_line { |l| warn "  [cms] #{l.chomp}" } }
      out = stdout.read
      err_thread.join
      status = wait.value
    end
    abort 'Listing tasks failed (see [cms] lines above).' unless status&.success?
    # Anything on stdout that isn't a bare valid task name is ignored --
    # defense in depth against stray library chatter leaking past the
    # snippet's own stdout discipline.
    out.to_s.each_line.map(&:chomp).select { |l| valid_name?(l) }
  end
end

namespace :cms do
  desc 'Clone a task from the remote CMS. Usage: rails "cms:clone[task_name]"'
  task :clone, %i[name] => :environment do |_t, args|
    require 'open3'
    require 'tmpdir'

    name = args[:name].to_s
    abort 'Usage: rails "cms:clone[<task_name>]"' if name.blank?
    # Task name goes onto the remote command line -- keep it shell-inert.
    abort "Task name '#{name}' contains unsupported characters" unless CmsClone.valid_name?(name)
    Current.actor_note = "Rake: cms:clone[#{name}]"

    host, python = CmsClone.resolve_settings
    abort 'Set CMS_SSH_HOST or create config/cms_remote.yml (see config/cms_remote.yml.sample)' if host.blank?

    if (existing = Problem.find_by(name: name))
      puts "NOTE: problem '#{name}' already exists (id #{existing.id}); " \
           'the import will ADD a new dataset generation to it (live dataset unchanged).'
    end

    script = Rails.root.join('script', 'cms_extract', 'extract_task.py')
    Dir.mktmpdir('cms_clone_') do |tmp|
      puts "Extracting '#{name}' from #{host} ..."
      result = CmsClone.clone_task(name: name, host: host, python: python, script: script, tmp: tmp)
      abort result.error unless result.ok

      avail_note = result.problem.available == false ? '; available=false until you enable it' : ''
      puts "Cloned '#{name}' -> problem id #{result.problem.id} " \
           "(#{result.dataset_count} dataset(s)#{avail_note})."
    end
  end

  desc 'Bulk-clone tasks from the remote CMS, dumping the server ONCE for the whole run. ' \
       'Usage: rails "cms:clone_all[name1,name2,...]" or rails "cms:clone_all[ALL]". ' \
       'FORCE=1 re-clones tasks whose Problem already exists locally (default: skip them).'
  task :clone_all, %i[names] => :environment do |_t, args|
    require 'open3'
    require 'tmpdir'
    require 'json'

    # Rake only maps the first bracket token to a declared arg name; args.to_a
    # gives every comma-separated token regardless of how many are declared,
    # which is what a variadic name list needs here.
    tokens = args.to_a.map(&:to_s).map(&:strip).reject(&:blank?)
    abort 'Usage: rails "cms:clone_all[<name1,name2,...>]" or rails "cms:clone_all[ALL]"' if tokens.empty?

    host, python = CmsClone.resolve_settings
    abort 'Set CMS_SSH_HOST or create config/cms_remote.yml (see config/cms_remote.yml.sample)' if host.blank?

    script = Rails.root.join('script', 'cms_extract', 'extract_task.py')
    bulk_dump_dir = "/tmp/cms_bulk_#{Time.now.strftime('%Y%m%d%H%M%S')}_#{Process.pid}"
    force = ENV['FORCE'] == '1'
    results = []

    begin
      names =
        if tokens == ['ALL']
          puts "Listing importable tasks (Batch, GroupMin/Sum) on #{host} ..."
          found = CmsClone.list_importable_tasks(host: host, python: python, dump_dir: bulk_dump_dir)
          abort 'No importable tasks found on the server.' if found.empty?
          puts "#{found.size} importable task(s) found."
          found
        else
          tokens
        end

      invalid = names.reject { |n| CmsClone.valid_name?(n) }
      abort "Task name(s) contain unsupported characters: #{invalid.join(', ')}" if invalid.any?

      Current.actor_note = "Rake: cms:clone_all (#{names.size} task(s), force=#{force})"

      names.each_with_index do |name, i|
        tag = "[#{i + 1}/#{names.size}] #{name} ..."

        if !force && Problem.exists?(name: name)
          puts "#{tag} SKIP (already imported)"
          results << { name: name, status: 'skipped', reason: 'already imported' }
          next
        end

        begin
          Dir.mktmpdir('cms_clone_') do |tmp|
            result = CmsClone.clone_task(name: name, host: host, python: python, script: script,
                                          tmp: tmp, dump_dir: bulk_dump_dir)
            if result.ok
              puts "#{tag} ok (problem id #{result.problem.id}, #{result.dataset_count} " \
                   "dataset(s), #{result.testcase_count} testcase(s))"
              results << { name: name, status: 'ok', problem_id: result.problem.id,
                           datasets: result.dataset_count, testcases: result.testcase_count }
            else
              label = result.stage == :convert ? 'REJECTED' : 'FAILED'
              puts "#{tag} #{label}: #{result.error}"
              results << { name: name, status: label.downcase, reason: result.error }
            end
          end
        rescue StandardError => e
          puts "#{tag} FAILED: #{e.class}: #{e.message}"
          results << { name: name, status: 'failed', reason: "#{e.class}: #{e.message}" }
        end
      end
    ensure
      # Single cleanup call for the whole run's shared dump, even on abort/crash.
      puts "Removing server-side dump dir #{bulk_dump_dir} ..."
      system('ssh', '-o', 'BatchMode=yes', host, 'sudo', '-n', '-u', 'cms', 'rm', '-rf', bulk_dump_dir)
    end

    ok      = results.select { |r| r[:status] == 'ok' }
    skipped = results.select { |r| r[:status] == 'skipped' }
    bad     = results.reject { |r| %w[ok skipped].include?(r[:status]) }

    puts ''
    puts "Summary: #{ok.size} ok, #{skipped.size} skipped, #{bad.size} failed/rejected " \
         "(of #{results.size} task(s))."
    bad.each { |r| puts "  #{r[:status].upcase} #{r[:name]}: #{r[:reason]}" }

    out_path = Rails.root.join('tmp', "cms_clone_all_#{Time.now.strftime('%Y%m%d%H%M%S')}.json")
    File.write(out_path, JSON.pretty_generate(results))
    puts "Summary written to #{out_path}"
  end
end
