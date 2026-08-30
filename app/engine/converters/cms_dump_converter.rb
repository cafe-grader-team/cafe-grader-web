require 'json'
require 'open3'
require 'fileutils'
require 'digest'

# Converts a CMS task bundle — produced by script/cms_extract/extract_task.py:
# the official cmsDumpExporter subtree (task.json) plus digest-addressed blobs
# (files/<sha1>) — into the canonical cafe staging directory consumed by
# ProblemImporter. Pure dir→dir; never touches the database.
#
# Multi-dataset: the CMS active dataset becomes the root (live) layout; every
# other importable dataset becomes datasets/<name>/ per the additive zip
# format (doc/multi-dataset-export-import-design-2026-07-16.md).
#
# Reject/skip matrix (spec §Rejection): non-Batch task type, file-I/O, and
# unsupported score types reject the TASK when found on the active dataset,
# and skip just that DATASET (warning) when found on a non-active one.
#
# On errors the staging dir may be partially written — callers must not
# import unless the returned :errors is empty.
# Spec: docs/superpowers/specs/2026-08-02-cms-clone-import-design.md
class Converters::CmsDumpConverter
  SUPPORTED_BUNDLE_VERSION = 1
  # cms.db version on c2 (CMS 1.4.dev3). On drift: re-verify the field mapping
  # against the new dump schema, then bump.
  SUPPORTED_DUMP_VERSION = 39

  SCORE_TYPE_MAP = { 'Sum' => 'sum', 'GroupMin' => 'group_min' }.freeze
  # 'comparator' maps to cms_comparator, NOT custom_testlib (formerly — and
  # misleadingly — named custom_cms): CMS invokes its checker as (input,
  # correct, USER) (cms/grading/steps/trusted.py), while custom_testlib is
  # cafe's testlib/Codeforces-order evaluator (input, USER, correct). Using
  # the testlib type here fed CMS checkers arguments in the wrong order (see
  # app/engine/checker.rb, doc/dataset-scoring-and-evaluation.md).
  EVAL_MAP       = { 'diff' => 'default', 'comparator' => 'cms_comparator' }.freeze

  # Cap on the scale factor k used by scale_group_min_weights! (see there).
  # Real CMS packages seen so far top out around k=100 (hundredths of a
  # point); a k above this cap would only come from synthetic/absurd
  # precision, where scaling every weight up would just produce huge,
  # meaningless integers for no real fidelity gain.
  GROUP_MIN_SCALE_CAP = 1000

  # Attachment filenames that would collide with ProblemImporter's root-level
  # recursive globs (*.pdf statement, *.md description, *.in/*.sol testcases)
  # or its recursive **/checker glob (a bare "checker" attachment) get
  # wrapped in a zip instead of shipped bare.
  RISKY_ATTACHMENT = /\.(pdf|md|in|sol|yml)\z|\Achecker\z/i

  # Manager/attachment names come from the bundle and are used as path
  # components; reject anything that isn't a plain filename before it
  # touches the filesystem.
  SAFE_FILENAME = /\A[\w.\-]+\z/

  # CMS testcase codenames are free-form authoring strings — some real Chula
  # tasks use directory-style codenames (e.g. "result/01-01", "../tests/01-01")
  # that are perfectly legitimate to CMS but unsafe as a bare filename (path
  # traversal / nested dirs). Grouping and ordering MUST still be computed on
  # the ORIGINAL codename (see build_group_plan) — this helper only maps a
  # codename to a safe on-disk name for the point where it is actually used
  # as a path component (see safe_codename_map / write_dataset_into).
  #
  # Public so other tools (e.g. a companion audit script) can reproduce the
  # exact same mapping.
  def self.safe_codename(name)
    s = name.to_s.gsub(/[^\w.\-]/, '_')
    # Guards degenerate results that would still be unsafe/meaningless as a
    # filename: '', '.', '..', or any string made up only of dots.
    s = "tc_#{Digest::MD5.hexdigest(name.to_s)[0, 8]}" if s.blank? || s.gsub('.', '').blank?
    # A result that still starts with a dot (e.g. "../tests/01-01" ->
    # ".._tests_01-01" after the gsub above) is filesystem-safe but becomes a
    # DOTFILE on disk -- and ProblemImporter#read_testcase finds testcases
    # via a plain Dir["**/*.in"], which (like Ruby glob in general) never
    # matches a leading dot without File::FNM_DOTMATCH. Without this, the
    # testcase is written successfully but is silently invisible to the
    # importer: a dataset can convert clean and still import as "ok, 0
    # testcase(s))" (the mar2023_updown incident: 167 "../tests/…" codenames,
    # 0 imported, no error anywhere). Collapse the entire leading run of dots
    # to a single underscore (".._tests_01-01" -> "__tests_01-01") --
    # deterministic and stable, since the replay gate
    # (app/engine/replay/cms_replay.rb) calls this same helper to match CMS
    # results back to cafe testcases.
    s = s.sub(/\A\.+/, '_')
    unless s.match?(SAFE_FILENAME) && !%w[. ..].include?(s) && !s.start_with?('.')
      # Defensive: should be unreachable given the sanitization above. Kept
      # so a future edit to this method can't silently regress the
      # filesystem-safety property it exists to guarantee.
      raise "Converters::CmsDumpConverter.safe_codename produced unsafe result " \
            "#{s.inspect} for input #{name.inspect}"
    end
    s
  end

  attr_reader :log, :warnings, :errors, :problem_meta

  def initialize
    @log = []
    @warnings = []
    @errors = []
    @problem_meta = {}
  end

  # bundle_dir: dir holding task.json + files/<digest>
  # staging_dir: output dir (created here)
  # => {log:, warnings:, errors:}
  def convert(bundle_dir, staging_dir)
    @bundle  = Pathname.new(bundle_dir)
    @staging = Pathname.new(staging_dir)
    catch(:reject) do
      parse_bundle
      plan_datasets
      write_staging
    end
    { log: @log, warnings: @warnings, errors: @errors }
  end

  private

  def reject!(msg)
    @errors << msg
    throw :reject
  end

  # Guarded @objects[id] lookup — the bundle's referential integrity (task ->
  # dataset -> manager/testcase/statement/attachment ids) is not verified by
  # the extractor, so a dangling id must reject! cleanly instead of raising
  # NoMethodError/EISDIR deep in a private helper.
  def fetch_obj(id)
    obj = @objects[id.to_s]
    reject!("bundle objects map is missing id #{id.inspect}") unless obj.is_a?(Hash)
    obj
  end

  def parse_bundle
    tj = @bundle + 'task.json'
    reject!("bundle has no task.json (#{tj})") unless tj.exist?
    @data = JSON.parse(File.read(tj))
    unless @data['bundle_version'] == SUPPORTED_BUNDLE_VERSION
      reject!("unsupported bundle_version #{@data['bundle_version'].inspect} " \
              "(supported: #{SUPPORTED_BUNDLE_VERSION})")
    end
    unless @data['dump_version'] == SUPPORTED_DUMP_VERSION
      reject!("unsupported CMS dump _version #{@data['dump_version'].inspect} " \
              "(supported: #{SUPPORTED_DUMP_VERSION}; re-verify the mapping " \
              'against the new dump schema before bumping SUPPORTED_DUMP_VERSION)')
    end
    @objects = @data['objects']
    reject!('bundle has no objects map') unless @objects.is_a?(Hash)
    @task = @objects[@data['task_id'].to_s]
    reject!('task_id missing from objects') unless @task && @task['_class'] == 'Task'
    @log << "task '#{@task['name']}' (#{@task['title']}), #{(@task['datasets'] || []).size} dataset(s)"
    @log << 'instance-local CMS fields skipped: token_*, max_submission_number, ' \
            'max_user_test_number, score_mode, score_precision, per-testcase public flags'
  end

  def plan_datasets
    active_id = @task['active_dataset'].to_s
    @active = fetch_obj(active_id)
    reasons = dataset_reject_reasons(@active)
    if reasons.any?
      reject!("active dataset '#{ds_display_name(@active)}': #{reasons.join('; ')}")
    end
    @others = []
    (@task['datasets'] || []).map(&:to_s).reject { |i| i == active_id }.each do |id|
      ds = fetch_obj(id)
      rs = dataset_reject_reasons(ds)
      if rs.any?
        @warnings << "skipped non-active dataset '#{ds_display_name(ds)}': #{rs.join('; ')}"
      else
        @others << ds
      end
    end
    @problem_meta = { name: @task['name'], full_name: @task['title'],
                      live_dataset_name: ds_display_name(@active) }
  end

  # Unsupported CMS features per the standing non-goals (doc/backlog.md):
  # Communication/OutputOnly/TwoSteps task types, file-I/O batch tasks,
  # GroupMinPrereq (and any other unknown) scoring.
  def dataset_reject_reasons(ds)
    unless ds['task_type'] == 'Batch'
      return ["task_type '#{ds['task_type']}' not supported (only Batch; see doc/backlog.md)"]
    end

    reasons = []
    compilation, io, eval_mode = ds['task_type_parameters']
    if io.is_a?(Array) && io.any? { |f| f.to_s != '' }
      reasons << "file-I/O task (infile/outfile #{io.inspect}) not supported (see doc/backlog.md)"
    end
    reasons << "unknown Batch compilation #{compilation.inspect}" unless %w[grader alone].include?(compilation)
    unless SCORE_TYPE_MAP.key?(ds['score_type'])
      reasons << "score_type '#{ds['score_type']}' not supported (GroupMinPrereq: see doc/backlog.md)"
    end
    reasons << "unknown Batch output evaluation #{eval_mode.inspect}" unless EVAL_MAP.key?(eval_mode)
    if eval_mode == 'comparator' && !(ds['managers'] || {}).key?('checker')
      reasons << "comparator evaluation but no 'checker' manager"
    end
    if compilation == 'grader' && (ds['managers'] || {}).keys.none? { |n| n != 'checker' && n.end_with?('.cpp') }
      reasons << 'grader compilation but no .cpp manager to use as main file'
    end
    if SCORE_TYPE_MAP.key?(ds['score_type'])
      _plan, plan_errors, = build_group_plan(ds)
      reasons.concat(plan_errors)
    end
    reasons
  end

  # => [ {codename => {group:, group_name:, weight:}}, [error strings], [warning strings] ]
  # Deterministic; called once for validation (dataset_reject_reasons, which
  # only looks at the error list) and once for writing (write_dataset_into,
  # which surfaces the warning list to @log). Operates entirely on ORIGINAL
  # CMS codenames, including directory-style ones (e.g. "result/01-01") —
  # that mirrors what CMS itself does: ScoreTypeGroup slices testcases in
  # lexicographic order of the raw codename, and GroupMin regex params are
  # re.match'd against the raw codename. Filesystem safety is handled
  # separately, at write time, via safe_codename_map — never here.
  def build_group_plan(ds)
    codenames = (ds['testcases'] || {}).keys

    # CMS ScoreTypeGroup consumes testcases in lexicographic codename order.
    sorted = codenames.sort
    case ds['score_type']
    when 'Sum'
      [sorted.to_h { |c| [c, { group: 1, group_name: '1', weight: 1 }] }, [], []]
    when 'GroupMin'
      params = ds['score_type_parameters']
      unless params.is_a?(Array) && params.all? { |p| p.is_a?(Array) && p.size == 2 }
        return [{}, ["GroupMin parameters malformed: #{params.inspect}"], []]
      end
      if params.all? { |_m, t| t.is_a?(Integer) }
        build_group_min_int_plan(params, sorted)
      elsif params.all? { |_m, t| t.is_a?(String) }
        plan = {}
        errs = []
        params.each_with_index do |(points, pattern), i|
          begin
            re = /\A(?:#{pattern})/ # CMS uses re.match => start-anchored
          rescue RegexpError => e
            errs << "GroupMin pattern #{pattern.inspect} is an invalid regex: #{e.message}"
            next
          end
          sorted.each do |c|
            next unless re.match?(c)
            if plan.key?(c)
              errs << "testcase '#{c}' matches multiple GroupMin patterns " \
                      "(groups #{plan[c][:group]} and #{i + 1})"
            else
              plan[c] = { group: i + 1, group_name: (i + 1).to_s, weight: points }
            end
          end
        end
        uncovered = sorted - plan.keys
        errs << "testcases match no GroupMin pattern: #{uncovered.join(', ')}" if uncovered.any?
        if errs.any?
          [{}, errs, []]
        else
          warnings = []
          scale_group_min_weights!(plan, warnings)
          [plan, errs, warnings]
        end
      else
        [{}, ['GroupMin parameters mix integer and regex styles (unsupported)'], []]
      end
    else
      [{}, [], []] # unreachable: score_type gated in dataset_reject_reasons
    end
  end

  # GroupMin with integer testcase-count params. CMS's own ScoreTypeGroup
  # walks sorted codenames and slices exactly `count` per subtask, in
  # declaration order — it does NOT require the counts to sum to the actual
  # testcase count. Real Chula tasks hit both mismatch directions:
  #   - params_sum < count: CMS simply leaves the trailing testcases out of
  #     any subtask — they're evaluated but never scored. Cafe's group_min
  #     scorer normalizes by total weight (app/engine/scorer.rb), so a
  #     weight-0 trailing group reproduces that exactly (contributes 0 to
  #     both numerator and denominator).
  #   - params_sum > count: a slice runs out of testcases before it gets its
  #     declared count (defensive slicing — Array#[] naturally caps at what's
  #     available); if a slice comes up completely empty, that whole group is
  #     dropped rather than emitted as a bogus zero-testcase group.
  # Only reject if NOTHING usable comes out of this (empty dataset or every
  # group empty and nothing left over) — that's genuinely unusable data.
  def build_group_min_int_plan(params, sorted)
    total = params.sum { |_m, t| t }
    plan = {}
    warnings = []
    dropped_groups = []
    cursor = 0
    params.each_with_index do |(points, count), i|
      slice = sorted[cursor, count] || []
      if slice.empty? && count.positive?
        dropped_groups << (i + 1)
      else
        slice.each { |c| plan[c] = { group: i + 1, group_name: (i + 1).to_s, weight: points } }
      end
      cursor += count
    end

    if dropped_groups.any?
      warnings << "GroupMin params declare #{total} testcases but only #{sorted.size} exist; " \
                  "group #{dropped_groups.join(', ')} is empty and was dropped — " \
                  'scores may not match CMS for this task'
    end

    if cursor < sorted.size
      leftover = sorted[cursor..] || []
      leftover_group = params.size + 1
      leftover.each { |c| plan[c] = { group: leftover_group, group_name: leftover_group.to_s, weight: 0 } }
      warnings << "GroupMin params cover #{total} of #{sorted.size} testcases; the remaining " \
                  "#{leftover.size} assigned to a weight-0 group (CMS ignores them for scoring)"
    end

    if plan.empty?
      [{}, ["GroupMin produced no usable testcase groups (params declare #{total}, " \
            "dataset has #{sorted.size} testcases)"], []]
    else
      scale_group_min_weights!(plan, warnings)
      [plan, [], warnings]
    end
  end

  # CMS GroupMin points may be fractional (e.g. a 100-point task split into
  # subtasks worth 1.5, 2.5, 11.5, ...), but cafe's testcases.weight column
  # is an integer, so copying points straight into weight would silently
  # truncate and change scores. group_min (app/engine/scorer.rb) normalises
  # by total weight -- Σ(min·weight) / Σweight × 100 -- so multiplying every
  # weight in the plan by the same positive integer k leaves the resulting
  # score identical. We therefore scale up to the smallest k that makes
  # every weight an exact integer, using exact rational arithmetic
  # (Rational(value.to_s), never float comparisons, so e.g. 0.1 + 0.2
  # binary-float noise can't produce a wrong k).
  #
  # Mutates plan in place; appends a warning to `warnings` (the same array
  # build_group_plan returns as its third element, which callers prefix
  # and surface into @log) iff scaling actually happened. Integer-only
  # points (the common case: 87 of 93 real tasks) are left byte-identical,
  # no warning.
  #
  # A weight-0 group (e.g. the uncovered-tail group from
  # build_group_min_int_plan) needs no special handling: Rational(0) has
  # denominator 1, so it never affects k, and 0 * k == 0.
  def scale_group_min_weights!(plan, warnings)
    present = plan.values.map { |v| v[:weight] }.uniq
    rationals = present.to_h { |w| [w, Rational(w.to_s)] }
    return if rationals.values.all? { |r| r.denominator == 1 } # already integral: no-op, no warning

    fractional = present.select { |w| rationals[w].denominator != 1 }
    sample = fractional.first(4).join(', ')
    sample += ', …' if fractional.size > 4
    k = rationals.values.map(&:denominator).reduce(1) { |a, b| a.lcm(b) }

    if k > GROUP_MIN_SCALE_CAP
      plan.each_value do |v|
        next if v[:weight].zero?

        v[:weight] = [rationals[v[:weight]].round, 1].max
      end
      warnings << "GroupMin points need scale factor #{k} (> #{GROUP_MIN_SCALE_CAP}) to become exactly " \
                  "integral (fractional points: #{sample}); rounding each weight to the nearest integer " \
                  'instead -- scores for this task may differ slightly from CMS'
    else
      plan.each_value { |v| v[:weight] = (rationals[v[:weight]] * k).to_i }
      warnings << "GroupMin points are fractional (#{sample}); all group weights scaled ×#{k} to stay " \
                  'integral -- scoring is unchanged because group_min normalises by total weight'
    end
  end

  # Original codename -> filesystem-safe codename, for one dataset's
  # testcases. Called at write time, AFTER build_group_plan has already
  # decided grouping/ordering on the originals — this only governs what
  # actually lands on disk / in config.yml. Two distinct originals sanitizing
  # to the same safe name would silently merge two testcases into one file,
  # so that's a hard reject! (practically impossible; loud failure is right).
  def safe_codename_map(codenames)
    orig_to_safe = {}
    safe_to_orig = {}
    codenames.each do |c|
      safe = self.class.safe_codename(c)
      if safe_to_orig.key?(safe) && safe_to_orig[safe] != c
        reject!("testcase codenames #{safe_to_orig[safe].inspect} and #{c.inspect} both " \
                "sanitize to the same filesystem-safe name #{safe.inspect} — cannot import " \
                '(rename one of them in the CMS source to disambiguate)')
      end
      safe_to_orig[safe] = c
      orig_to_safe[c] = safe
    end
    orig_to_safe
  end

  def write_staging
    @staging.mkpath
    cfg = problem_level_config
    write_dataset_into(@active, @staging, cfg)
    write_statement
    write_attachments
    additional = []
    # ProblemImporter matches additional datasets BY NAME (ds_name), so two
    # CMS datasets that display the same name (or the active dataset's own
    # name) must not collide silently into one cafe dataset on import.
    used_ds_names = [ds_display_name(@active)]
    @others.each do |ds|
      display_name = ds_display_name(ds)
      dirname = unique_dirname(additional, display_name)
      ds_name = unique_ds_name(used_ds_names, display_name)
      if ds_name != display_name
        @warnings << "dataset '#{display_name}' renamed to '#{ds_name}' in additional_datasets " \
                     "to avoid colliding with another dataset's name"
      end
      ds_compilation = ds['task_type_parameters']&.first
      active_compilation = @active['task_type_parameters']&.first
      if ds_compilation != active_compilation
        @warnings << "dataset '#{display_name}': compilation '#{ds_compilation}' differs from " \
                     "the active dataset's '#{active_compilation}' — problem-level compilation_type " \
                     'follows the ACTIVE dataset; promoting this dataset live later needs a manual ' \
                     'compilation_type change'
      end
      dir = @staging + ProblemImporter::RESERVED_DATASETS_DIRNAME + dirname
      frag = { ds_name: ds_name }
      write_dataset_into(ds, dir, frag)
      write_yaml(dir + OptionConst::YAML_FILENAME, frag)
      additional << dirname
      used_ds_names << ds_name
      @log << "additional dataset '#{ds_name}' -> " \
              "#{ProblemImporter::RESERVED_DATASETS_DIRNAME}/#{dirname}/"
    end
    cfg[:additional_datasets] = additional if additional.any?
    write_yaml(@staging + OptionConst::YAML_FILENAME, cfg)
    @log << 'staging dir ready'
  end

  def problem_level_config
    compilation, _io, _eval_mode = @active['task_type_parameters']
    fmt = @task['submission_format'] || []
    if fmt.size != 1
      @warnings << "submission_format has #{fmt.size} entries (#{fmt.inspect}); using the first"
    end
    submission_filename = (fmt.first || "#{@task['name']}.%l").gsub('%l', 'cpp')
    cfg = {
      name: @task['name'],
      full_name: @task['title'],
      task_type: 'batch',
      compilation_type: compilation == 'grader' ? 'with_managers' : 'self_contained',
      submission_filename: submission_filename,
      ds_name: ds_display_name(@active)
    }
    # Grader-linked tasks compile as C++ on the cafe judge (compiler/cpp.rb
    # globs manager + submission .cpp files together).
    cfg[:permitted_lang] = 'cpp' if compilation == 'grader'
    cfg
  end

  # Writes ds's files under dir and fills cfg with the dataset-scoped fields
  # (OptionConst::DATASET_OPTION_FIELDS subset) + the testcases hash.
  def write_dataset_into(ds, dir, cfg)
    dir.mkpath
    compilation, _io, eval_mode = ds['task_type_parameters']
    cfg[:time_limit]      = ds['time_limit'].to_f
    cfg[:memory_limit]    = ds['memory_limit'].to_i
    cfg[:score_type]      = SCORE_TYPE_MAP.fetch(ds['score_type'])
    cfg[:evaluation_type] = EVAL_MAP.fetch(eval_mode)
    # ProblemImporter#read_cpp_extras globs additional managers at
    # @options[:managers_dir] with @options[:managers_pattern], root-level
    # only (recursive: false) — without these, managers/*.h land on disk but
    # the importer never looks in managers/ and silently skips them.
    cfg[:managers_dir]     = OptionConst::DEFAULT[:dir][:managers]
    cfg[:managers_pattern] = '*'

    managers = ds['managers'] || {}
    if (checker_id = managers['checker'])
      copy_blob(fetch_obj(checker_id)['digest'], dir + 'checker' + 'checker')
      @warnings << "dataset '#{ds_display_name(ds)}': CMS comparator copied as checker/checker — " \
                   'CMS checkers are prebuilt binaries; verify it runs on the cafe judge host ' \
                   '(or replace with recompiled source)'
    end
    manager_names = managers.keys - ['checker']
    bad_manager = manager_names.find { |name| !name.match?(SAFE_FILENAME) }
    reject!("unsafe manager filename #{bad_manager.inspect}") if bad_manager
    manager_names.each do |name|
      copy_blob(fetch_obj(managers[name])['digest'], dir + 'managers' + name)
    end
    if compilation == 'grader'
      main = manager_names.include?('grader.cpp') ? 'grader.cpp' : manager_names.sort.find { |n| n.end_with?('.cpp') }
      cfg[:main] = [main]
      cfg[:main_filename] = main
    end

    # Grouping/ordering is decided on the ORIGINAL codenames (build_group_plan
    # never sees the sanitized form). Only when actually emitting to disk /
    # config.yml do we translate to filesystem-safe names.
    plan, _errs, plan_warnings = build_group_plan(ds)
    plan_warnings.each { |w| @log << "dataset '#{ds_display_name(ds)}': #{w}" }
    if ds['score_type'] == 'Sum'
      @log << "dataset '#{ds_display_name(ds)}': CMS Sum " \
              "(params #{ds['score_type_parameters'].inspect}) -> cafe sum, every testcase weight 1"
    end
    safe_map = safe_codename_map((ds['testcases'] || {}).keys)
    tc_cfg = {}
    (ds['testcases'] || {}).sort.each do |codename, tc_id|
      tc = fetch_obj(tc_id)
      safe = safe_map.fetch(codename)
      copy_blob(tc['input'],  dir + 'testcases' + "#{safe}.in")
      copy_blob(tc['output'], dir + 'testcases' + "#{safe}.sol")
      tc_cfg[safe] = plan[codename]
    end
    cfg[:testcases] = tc_cfg

    # Refuse to hand ProblemImporter a dataset that LOOKS converted but is
    # silently empty (or short) to it. This is the direct regression guard
    # for the mar2023_updown incident: every testcase above can copy_blob
    # successfully and land in tc_cfg, yet still be invisible at import time
    # if it ended up a dotfile (or any other future bug drops it from the
    # importer's view). Reproduce ProblemImporter#read_testcase's exact glob
    # (Dir[...], no File::FNM_DOTMATCH) and compare by EQUALITY against the
    # bundle's testcase count -- not "> 0" -- because some real CMS tasks
    # (please_ignore, tennisballs) legitimately have zero testcases and must
    # still convert cleanly (0 == 0 passes).
    bundle_tc_count = (ds['testcases'] || {}).size
    emitted_tc_count = Dir.glob((dir + 'testcases' + '*.in').to_s).size
    if emitted_tc_count != bundle_tc_count
      reject!("dataset '#{ds_display_name(ds)}': bundle has #{bundle_tc_count} testcase(s) but " \
              "only #{emitted_tc_count} would be visible to ProblemImporter's testcase glob " \
              '(internal inconsistency -- refusing to emit a silently-broken dataset)')
    end

    rewritten = safe_map.reject { |orig, safe| orig == safe }
    if rewritten.any?
      sample = rewritten.first(5).map { |orig, safe| "#{orig} -> #{safe}" }.join(', ')
      more = rewritten.size > 5 ? ", ... (#{rewritten.size} total)" : ''
      @log << "dataset '#{ds_display_name(ds)}': #{rewritten.size} testcase codename(s) " \
              "sanitized for filesystem safety: #{sample}#{more}"
    end
    @log << "dataset '#{ds_display_name(ds)}': #{tc_cfg.size} testcases, " \
            "#{plan.values.map { |v| v[:group] }.uniq.size} group(s)"
  end

  def write_statement
    statements = @task['statements'] || {}
    if statements.empty?
      @warnings << 'task has no statement PDF'
      return
    end
    primary = (@task['primary_statements'] || []).first
    lang = [primary, 'th', 'en'].compact.find { |l| statements.key?(l) } || statements.keys.sort.first
    copy_blob(fetch_obj(statements[lang])['digest'], @staging + OptionConst::DEFAULT[:file][:statement])
    @log << "statement: language '#{lang}' -> #{OptionConst::DEFAULT[:file][:statement]}"
    (statements.keys - [lang]).sort.each do |l|
      @warnings << "statement language '#{l}' skipped (cafe holds one statement)"
    end
  end

  def write_attachments
    atts = (@task['attachments'] || {}).map { |name, id| [name, fetch_obj(id)['digest']] }
    return if atts.empty?

    bad_attachment = atts.map(&:first).find { |name| !name.match?(SAFE_FILENAME) }
    reject!("unsafe attachment filename #{bad_attachment.inspect}") if bad_attachment

    dir = @staging + OptionConst::DEFAULT[:dir][:attachment]
    if atts.size == 1 && atts.first.first !~ RISKY_ATTACHMENT
      name, digest = atts.first
      copy_blob(digest, dir + name)
      @log << "attachment: #{name}"
    else
      tmp = @staging + 'attachment_tmp'
      atts.each { |name, digest| copy_blob(digest, tmp + name) }
      dir.mkpath
      zip_name = "#{@task['name']}-files.zip"
      out, err, status = Open3.capture3('zip', '-j', (dir + zip_name).to_s,
                                        *atts.map { |name, _| (tmp + name).to_s })
      reject!("zip of attachments failed: #{err.presence || out}") unless status.success?
      FileUtils.rm_rf(tmp)
      @log << "attachments bundled into #{zip_name}: #{atts.map(&:first).join(', ')}"
    end
  end

  def copy_blob(digest, dest)
    # A blank digest would resolve to @bundle/files itself (the directory),
    # which #exist? reports true for — cp then blows up with Errno::EISDIR
    # instead of a clean reject!. Catch it here, before building src.
    reject!("bundle blob digest missing/blank for #{dest}") if digest.to_s.strip.empty?
    src = @bundle + 'files' + digest.to_s
    reject!("bundle blob missing: #{digest}") unless src.exist?
    dest.dirname.mkpath
    FileUtils.cp(src, dest)
  end

  def ds_display_name(ds)
    ds['description'].presence || 'unnamed'
  end

  def unique_dirname(taken, display_name)
    base = display_name.parameterize
    base = 'dataset' if base.blank?
    candidate = base
    n = 1
    while taken.include?(candidate)
      n += 1
      candidate = "#{base}-#{n}"
    end
    candidate
  end

  # Same collision-avoidance shape as unique_dirname, but on the raw
  # (unparameterized) display name — this becomes the ds_name written into
  # config.yml, which ProblemImporter uses to MATCH additional datasets.
  def unique_ds_name(taken, display_name)
    candidate = display_name
    n = 1
    while taken.include?(candidate)
      n += 1
      candidate = "#{display_name}-#{n}"
    end
    candidate
  end

  def write_yaml(path, hash)
    path.dirname.mkpath
    File.write(path, hash.deep_stringify_keys.to_yaml)
  end
end
