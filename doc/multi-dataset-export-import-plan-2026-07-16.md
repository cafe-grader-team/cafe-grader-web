# Multi-Dataset Export/Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export/import *all* of a problem's datasets (not just the live one) via a backward-compatible additive `.zip` format, with a live-only/all toggle on export (operator kwarg + rake **and** a web download dropdown) and an import that reads whatever datasets the package contains.

**Architecture:** Refactor `ProblemExporter` so dataset-scoped writes target an arbitrary dir + its own options hash (`export_dataset_files(ds, dir, opts)`); the live dataset writes to root (byte/semantically unchanged), additional datasets write to `datasets/<name>/` with a per-dataset `config.yml` fragment, and the root config gains an `additional_datasets:` key. `ProblemImporter` gains `import_additional_datasets`, which reuses the existing (trusted) dataset-scoped read methods by temporarily pointing them at each subdir. Spec: `doc/multi-dataset-export-import-design-2026-07-16.md`.

**Tech Stack:** Ruby 3.4.4 / Rails 8.0, minitest, ActiveStorage (`:test` service), HAML + Bootstrap dropdown, Mercurial.

## Global Constraints

- **VCS is Mercurial.** Before EVERY commit: `hg log -r . --template '{activebookmark}\n'` MUST print `master` (else `hg update master`). Name explicit files in every `hg commit`. End messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **CHANGELOG.md** bullet only in the final task (feature is user-facing once the surface lands); intermediate tasks are internal refactor/plumbing — no changelog.
- **Backward compatibility is the hard requirement.** The live-only export (default) must remain semantically identical to today (same parsed `config.yml` + same file tree), and every existing single-dataset zip must still import unchanged. Task 1 pins this before any refactor.
- Run tests with `bin/rails test <path>`. Do NOT run `bin/rails check` per task. `rubocop` the touched files each task.
- Trusted production code: make only the changes specified. The importer's intricate `read_*` methods are reused as-is (via temporary instance-var swap) — do NOT rewrite them.
- Additional datasets are **never** made live; the root dataset stays live. Re-import matches additional datasets **by name** (idempotent — no duplicate pile-up).

## File Structure

- `app/engine/problem_exporter.rb` — **modify**: extract `export_dataset_files` + `*_to` helpers; `export_problem_to_dir(..., all_datasets:)`; `export_root_options`.
- `app/engine/problem_importer.rb` — **modify**: `import_additional_datasets`; `do_additional_datasets:` kwarg.
- `app/engine/option_const.rb` — **modify**: add `YAML_KEY[:additional_datasets]`.
- `app/models/problem.rb` — **modify**: `export(all_datasets:)`.
- `app/controllers/problems_controller.rb` — **modify**: `download_archive` reads `all_datasets` param.
- `app/views/problems/edit.html.haml` — **modify**: download button → dropdown (live / all).
- `lib/tasks/*.rake` — **create/modify**: rake export with all-datasets flag.
- `test/engine/problem_multidataset_test.rb` — **create**: exporter/importer/round-trip tests.
- `test/controllers/problems_controller_test.rb` — **modify**: download_archive all_datasets test.
- `CHANGELOG.md` — **modify** (final task).

---

### Task 1: Pin the live-only export (characterization)

**Files:**
- Test (create): `test/engine/problem_multidataset_test.rb`

**Interfaces:**
- Produces: helper `import_rich(name)` and `parsed_config(dir)` used by later tasks.

This test captures today's live-only export so the Task 2 refactor cannot change it. It must PASS as-is.

- [ ] **Step 1: Write the characterization test**

```ruby
# test/engine/problem_multidataset_test.rb
require "test_helper"
require "tmpdir"

class ProblemMultidatasetTest < ActiveSupport::TestCase
  EXAMPLES = Rails.root.join("test", "problem_examples")

  def import_rich(name)
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(EXAMPLES.join("rich").to_s, name, user: users(:admin))
    pi.problem.reload
  end

  def parsed_config(dir)
    YAML.safe_load(File.read(File.join(dir, "config.yml")), symbolize_names: true)
  end

  # relative paths of every file under `dir`, sorted
  def file_tree(dir)
    Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }
       .map { |f| f.sub("#{dir}/", "") }.sort
  end

  test "live-only export produces a config with the expected keys and file tree" do
    p = import_rich("md_char")
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: dump, zip: false)
      dir = File.join(dump, p.name.parameterize)
      cfg = parsed_config(dir)

      # problem + dataset fields present, no multi-dataset key
      assert_equal "md_char", cfg[:name]
      assert_equal "with_managers", cfg[:compilation_type]
      assert_equal "group_min", cfg[:score_type]
      assert cfg.key?(:testcases), "testcases hash present"
      refute cfg.key?(:additional_datasets), "no additional_datasets in a live-only export"

      tree = file_tree(dir)
      assert_includes tree, "config.yml"
      assert(tree.any? { |f| f.start_with?("testcases/") }, "has testcases/")
      assert(tree.none? { |f| f.start_with?("datasets/") }, "no datasets/ dir in live-only")
    end
  end
end
```

- [ ] **Step 2: Run — expect PASS**

Run: `bin/rails test test/engine/problem_multidataset_test.rb`
Expected: `1 runs, 0 failures, 0 errors`. If it fails, STOP and report — the baseline is wrong.

- [ ] **Step 3: Commit** (no changelog — test only)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add test/engine/problem_multidataset_test.rb
hg commit test/engine/problem_multidataset_test.rb -m "test: characterize live-only export (guards the multi-dataset refactor)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Refactor exporter to `export_dataset_files(ds, dir, opts)`

**Files:**
- Modify: `app/engine/problem_exporter.rb`
- Test: `test/engine/problem_multidataset_test.rb` (Task 1's test guards this)

**Interfaces:**
- Produces: `export_dataset_files(ds, dir, opts)` (writes ds's dataset-scoped files under `dir`, fills `opts`); `export_root_options` (problem fields + writes root config.yml). Task 3 consumes both.

This is a **pure refactor** — the live-only output must stay semantically identical (Task 1 passes unchanged).

- [ ] **Step 1: Replace the dataset-scoped methods with parameterized `*_to` helpers + `export_dataset_files`**

Replace `export_testcases`, `export_managers_checker`, `export_initializers`, `export_data_files` with:

```ruby
  def export_testcases_to(ds, dir, opts)
    tc_dir = dir + OptionConst::DEFAULT[:dir][:testcases]
    tc_dir.mkpath
    tc_options = {}
    ds.testcases.each do |tc|
      basename = tc.code_name || tc.num
      tc_options[basename] = { group: tc.group, group_name: tc.group_name, weight: tc.weight }
      File.open(tc_dir + "#{basename}.#{@inp_ext}", 'w:ASCII-8BIT') { |f| tc.inp_file.download { |c| f.write(c) } }
      File.open(tc_dir + "#{basename}.#{@ans_ext}", 'w:ASCII-8BIT') { |f| tc.ans_file.download { |c| f.write(c) } }
    end
    opts[OptionConst::YAML_KEY[:testcases_pattern]] = '*'
    opts[OptionConst::YAML_KEY[:dir][:testcases]] = OptionConst::DEFAULT[:dir][:testcases]
    opts[OptionConst::YAML_KEY[:testcases]] = tc_options
  end

  def export_managers_checker_to(ds, dir, opts)
    manager_dir = dir + OptionConst::DEFAULT[:dir][:managers]
    manager_dir.mkpath
    ds.managers.each do |mng|
      File.open(manager_dir + mng.filename.to_s, 'w:ASCII-8BIT') { |f| mng.download { |c| f.write c } }
      opts[OptionConst::YAML_KEY[:managers_pattern]] = '*'
    end

    return unless ds.checker.attached?

    checker_dir = dir + OptionConst::DEFAULT[:dir][:checker]
    checker_dir.mkpath
    checker_fn = checker_dir + OptionConst::DEFAULT[:file][:checker]
    File.open(checker_fn, 'w:ASCII-8BIT') { |f| ds.checker.download { |c| f.write c } }
    opts[OptionConst::YAML_KEY[:checker]] = checker_fn.basename.to_s
  end

  def export_initializers_to(ds, dir)
    init_dir = dir + OptionConst::DEFAULT[:dir][:initializers]
    init_dir.mkpath
    ds.initializers.each { |m| File.open(init_dir + m.filename.to_s, 'w:ASCII-8BIT') { |f| m.download { |c| f.write c } } }
  end

  def export_data_files_to(ds, dir)
    df_dir = dir + OptionConst::DEFAULT[:dir][:data_files]
    df_dir.mkpath
    ds.data_files.each { |df| File.open(df_dir + df.filename.to_s, 'w:ASCII-8BIT') { |f| df.download { |c| f.write c } } }
  end

  # Write all of `ds`'s dataset-scoped files under `dir` and populate `opts`
  # with that dataset's config (testcases, dir keys, dataset fields, ds_name).
  def export_dataset_files(ds, dir, opts)
    export_testcases_to(ds, dir, opts)
    export_managers_checker_to(ds, dir, opts)
    export_initializers_to(ds, dir)
    export_data_files_to(ds, dir)

    OptionConst::DATASET_OPTION_FIELDS.each do |opt|
      value = ds.send(opt)
      next if value.blank?
      value = value.to_f if value.is_a?(BigDecimal)
      opts[opt] = value
    end
    opts[OptionConst::YAML_KEY[:ds_name]] = ds.name
    opts[OptionConst::YAML_KEY[:dir][:managers]] = OptionConst::DEFAULT[:dir][:managers]
    opts[OptionConst::YAML_KEY[:dir][:checker]] = OptionConst::DEFAULT[:dir][:checker]
    opts[OptionConst::YAML_KEY[:dir][:initializers]] = OptionConst::DEFAULT[:dir][:initializers]
    opts[OptionConst::YAML_KEY[:dir][:data_files]] = OptionConst::DEFAULT[:dir][:data_files]
  end
```

(Note: this drops the old absolute-then-relative `checker_dir` quirk — `checker_dir` is now set once, relative, in `export_dataset_files`. Final value is unchanged.)

- [ ] **Step 2: Replace `export_options` with `export_root_options` (problem-scoped only)**

```ruby
  # Problem-scoped options + write the root config.yml. Dataset fields/testcases
  # for the live dataset are already in @options via export_dataset_files.
  def export_root_options
    p_options = [:name] + OptionConst::PROBLEM_OPTION_FIELDS
    p_options.each do |opt|
      value = @problem.send(opt)
      next if value.blank?
      value = value.to_f if value.is_a?(BigDecimal)
      @options[opt] = value
    end
    @options[:markdown] = !!@problem.markdown if @problem.description.present?
    @options[OptionConst::YAML_KEY[:dir][:model_sols]] = OptionConst::DEFAULT[:dir][:model_sols]
    @options[OptionConst::YAML_KEY[:tags]] = @problem.tags.pluck(:name) if @problem.tags.count.positive?

    File.write(@main_dir + OptionConst::YAML_FILENAME, @options.deep_stringify_keys.to_yaml)
  end
```

- [ ] **Step 3: Rewire `export_problem_to_dir` to use them (live dataset only for now)**

Replace the export-body between `FileUtils.rm_rf(@main_dir)` and `result[:status] = :ok`:

```ruby
    @options = {}
    export_pdf
    export_attachment
    export_description
    export_dataset_files(@ds, @main_dir, @options)   # live dataset -> root
    export_root_options
    export_solutions
    result[:status] = :ok
```

(Keep the `@ds = @problem.live_dataset` / `raise 'No live dataset'` lines and the zip block unchanged. `export_options` no longer exists — confirm no other reference remains: `grep -n export_options app/engine/problem_exporter.rb` should be empty.)

- [ ] **Step 4: Run — expect PASS (Task 1's characterization holds)**

Run: `bin/rails test test/engine/problem_multidataset_test.rb test/engine/problem_round_trip_test.rb`
Expected: `0 failures, 0 errors` — the round-trip parity test from Package 1 and the characterization both still pass, proving the refactor is behavior-neutral.

- [ ] **Step 5: Rubocop + commit** (no changelog — internal refactor)

```bash
bundle exec rubocop app/engine/problem_exporter.rb
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_exporter.rb -m "refactor(export): parameterize dataset-scoped export on (ds, dir, opts)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Exporter `all_datasets:` option

**Files:**
- Modify: `app/engine/problem_exporter.rb`, `app/engine/option_const.rb`
- Test: `test/engine/problem_multidataset_test.rb`

**Interfaces:**
- Consumes: `export_dataset_files` (T2).
- Produces: `export_problem_to_dir(problem, base_dir:, zip: false, all_datasets: false)`; `OptionConst::YAML_KEY[:additional_datasets] == :additional_datasets`. Tasks 4–7 consume these.

- [ ] **Step 1: Add the YAML key**

In `app/engine/option_const.rb`, add to the `YAML_KEY` hash (top level, next to `ds_name`):

```ruby
    ds_name: :ds_name,
    additional_datasets: :additional_datasets,
```

- [ ] **Step 2: Write the failing test**

```ruby
  test "all_datasets export writes each non-live dataset under datasets/ with a fragment" do
    p = import_rich("md_all")
    # add a second, non-live dataset with its own testcase
    ds2 = Dataset.create!(problem: p, name: "Alt DS", time_limit: 3, memory_limit: 128, score_type: :sum)
    tc = Testcase.new(code_name: "9", num: 1, group: 1, weight: 5)
    tc.inp_file.attach(io: StringIO.new("9 9\n"), filename: "input.txt", content_type: "text/plain")
    tc.ans_file.attach(io: StringIO.new("18\n"), filename: "answer.txt", content_type: "text/plain")
    ds2.testcases << tc
    ds2.save!

    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: dump, zip: false, all_datasets: true)
      dir = File.join(dump, p.name.parameterize)
      cfg = parsed_config(dir)

      assert_equal ["alt-ds"], cfg[:additional_datasets]
      sub = File.join(dir, "datasets", "alt-ds")
      assert File.directory?(sub), "datasets/alt-ds/ exists"
      frag = YAML.safe_load(File.read(File.join(sub, "config.yml")), symbolize_names: true)
      assert_equal "Alt DS", frag[:ds_name]
      assert_equal 3.0, frag[:time_limit]
      assert frag[:testcases].key?("9".to_sym) || frag[:testcases].key?("9"), "fragment has the testcase weight entry"
      assert File.exist?(File.join(sub, "testcases", "9.in")), "additional dataset testcase exported"
      refute frag.key?(:name), "fragment carries no problem-level fields"
    end
  end
```

- [ ] **Step 3: Run — expect FAIL** (`all_datasets` kwarg unknown / no `datasets/` dir)

Run: `bin/rails test test/engine/problem_multidataset_test.rb`

- [ ] **Step 4: Implement — `all_datasets` in `export_problem_to_dir`**

Change the signature to add `all_datasets: false`, and insert the additional-dataset loop **after** `export_dataset_files(@ds, @main_dir, @options)` and **before** `export_root_options`:

```ruby
    export_dataset_files(@ds, @main_dir, @options)   # live dataset -> root

    if all_datasets
      taken = []
      @problem.datasets.where.not(id: @ds.id).order(:id).each do |ds|
        dirname = unique_ds_dirname(ds, taken)
        taken << dirname
        sub = @main_dir + 'datasets' + dirname
        frag = {}
        export_dataset_files(ds, sub, frag)
        File.write(sub + OptionConst::YAML_FILENAME, frag.deep_stringify_keys.to_yaml)
      end
      @options[OptionConst::YAML_KEY[:additional_datasets]] = taken unless taken.empty?
    end

    export_root_options
```

Add the helper:

```ruby
  # A filesystem-safe, unique subdir name for a dataset (parameterized name,
  # de-duplicated against names already used in this export).
  def unique_ds_dirname(ds, taken)
    base = ds.name.parameterize
    base = 'dataset' if base.blank?
    name = base
    i = 2
    while taken.include?(name)
      name = "#{base}-#{i}"
      i += 1
    end
    name
  end
```

- [ ] **Step 5: Run — expect PASS** (and re-run the characterization: live-only still has no `datasets/`)

Run: `bin/rails test test/engine/problem_multidataset_test.rb`

- [ ] **Step 6: Rubocop + commit** (no changelog — surface lands in Task 7/8)

```bash
bundle exec rubocop app/engine/problem_exporter.rb app/engine/option_const.rb
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_exporter.rb app/engine/option_const.rb test/engine/problem_multidataset_test.rb -m "feat(export): all_datasets option writes non-live datasets under datasets/

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Importer `import_additional_datasets`

**Files:**
- Modify: `app/engine/problem_importer.rb`
- Test: `test/engine/problem_multidataset_test.rb`

**Interfaces:**
- Consumes: `OptionConst::YAML_KEY[:additional_datasets]` (T3); the existing `read_testcase`/`read_checker`/`read_cpp_extras`/`read_initializers`/`read_data_files`/`read_options`.
- Produces: `import_dataset_from_dir(..., do_additional_datasets: true)` and `import_additional_datasets`. Task 5 relies on the multi-dataset import working end to end.

The existing dataset-scoped `read_*` methods lean on `@base_dir`/`@dataset`/`@options`. Reuse them by **temporarily swapping** those instance vars per subdir — do NOT rewrite the trusted read logic.

- [ ] **Step 1: Write the failing test**

```ruby
  test "import reads additional datasets from datasets/ into non-live datasets" do
    src = import_rich("md_imp_src")
    ds2 = Dataset.create!(problem: src, name: "Extra DS", time_limit: 2, memory_limit: 64, score_type: :sum)
    tc = Testcase.new(code_name: "7", num: 1, group: 1, weight: 3)
    tc.inp_file.attach(io: StringIO.new("7\n"), filename: "input.txt", content_type: "text/plain")
    tc.ans_file.attach(io: StringIO.new("7\n"), filename: "answer.txt", content_type: "text/plain")
    ds2.testcases << tc
    ds2.save!
    live_name = src.live_dataset.name

    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)

      pi = ProblemImporter.new
      pi.import_dataset_from_dir(exported, "md_imp_dst", user: users(:admin))
      dst = pi.problem.reload

      assert_equal 2, dst.datasets.count, "both datasets imported"
      extra = dst.datasets.find_by(name: "Extra DS")
      assert extra, "additional dataset created by name"
      refute_equal extra.id, dst.live_dataset.id, "additional dataset is NOT live"
      assert_equal 2.0, extra.time_limit.to_f
      assert_equal 1, extra.testcases.count
      assert_equal "7\n", extra.testcases.first.inp_file.download
      # live dataset still imported as today
      assert dst.live_dataset.testcases.count.positive?
    end
  end

  test "re-importing all-datasets onto the same problem does not duplicate additional datasets" do
    src = import_rich("md_idem_src")
    Dataset.create!(problem: src, name: "Once DS", time_limit: 1, memory_limit: 64, score_type: :sum).tap do |d|
      tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
      tc.inp_file.attach(io: StringIO.new("1\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("1\n"), filename: "a", content_type: "text/plain")
      d.testcases << tc; d.save!
    end
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)
      ProblemImporter.new.import_dataset_from_dir(exported, "md_idem_dst", user: users(:admin))
      ProblemImporter.new.import_dataset_from_dir(exported, "md_idem_dst", user: users(:admin))
    end
    dst = Problem.find_by(name: "md_idem_dst")
    assert_equal 1, dst.datasets.where(name: "Once DS").count, "additional dataset matched by name, not duplicated"
  end
```

- [ ] **Step 2: Run — expect FAIL** (only 1 dataset imported)

Run: `bin/rails test test/engine/problem_multidataset_test.rb`

- [ ] **Step 3a: Exclude the reserved `datasets/` subtree from the root's recursive globs**

The root import's two whole-tree recursive globs — `read_testcase` (`Dir["#{@base_dir}/**/…"]`, two occurrences) and `get_content_of_first_match` (`Dir.glob(pattern)…`) — otherwise descend into `datasets/<name>/`, causing "Found multiples of config.yml" (→ options lost) and slurping nested testcases into the live dataset. Add a guard so root-level reads skip that subtree. (During an *additional* dataset's import, `@base_dir` is the subdir itself, which has no nested `datasets/`, so the guard is a harmless no-op there.)

Add a constant near the top of `ProblemImporter` (after `attr_reader …`):

```ruby
  RESERVED_DATASETS_DIRNAME = 'datasets'
```

Add a helper (near `get_content_of_first_match`):

```ruby
  # Root-level recursive reads must not descend into the reserved datasets/
  # subtree — it holds additional datasets, imported separately by
  # import_additional_datasets.
  def outside_reserved_datasets?(path)
    reserved = File.join(@base_dir.to_s, RESERVED_DATASETS_DIRNAME) + '/'
    !path.to_s.start_with?(reserved)
  end
```

In `read_testcase`, filter BOTH globs:

```ruby
    Dir["#{@base_dir}/**/#{input_pattern}"].select { |fn| outside_reserved_datasets?(fn) }.each do |fn|
```
```ruby
    Dir["#{@base_dir}/**/#{sol_pattern}"].select { |fn| outside_reserved_datasets?(fn) }.each do |fn|
```

In `get_content_of_first_match`, change the file selection:

```ruby
    files = Dir.glob(pattern).select { |p| File.file?(p) && outside_reserved_datasets?(p) }
```

This does not affect live-only imports (no `datasets/` dir → no-op), so the Task 1 characterization / round-trip guardrails stay green.

- [ ] **Step 3b: Implement `import_additional_datasets`**

Add the kwarg `do_additional_datasets: true,` to `import_dataset_from_dir` (next to `do_data_files: true,`), and call it near the end — right after `warn_mixed_group_weights` (which follows `read_options`):

```ruby
    read_options # options is put to last, it will override any defaults
    warn_mixed_group_weights
    import_additional_datasets if do_additional_datasets
```

Add the method:

```ruby
  # Import any datasets listed under the root config's additional_datasets key,
  # each from datasets/<name>/, as NON-live datasets on @problem. Reuses the
  # existing dataset-scoped read methods by pointing them at the subdir.
  def import_additional_datasets
    names = @options[OptionConst::YAML_KEY[:additional_datasets]]
    return unless names.is_a?(Array)

    outer_base, outer_dataset, outer_options = @base_dir, @dataset, @options
    problem = outer_dataset.problem
    begin
      names.each do |dirname|
        subdir = Pathname.new(outer_base) + 'datasets' + dirname.to_s
        unless subdir.exist?
          @log << "WARNING: additional dataset dir missing: #{subdir}"
          next
        end

        cfg = subdir + OptionConst::YAML_FILENAME
        @options = cfg.exist? ? YAML.safe_load(File.read(cfg), symbolize_names: true) : {}
        @base_dir = subdir.to_s
        display_name = @options[OptionConst::YAML_KEY[:ds_name]] || dirname
        @dataset = problem.datasets.where(name: display_name).first ||
                   Dataset.new(name: display_name, problem: problem)
        @dataset.save

        read_testcase('*.in', '*.sol', /(.*)/, /^(\d+)-/)
        read_checker
        read_cpp_extras
        read_initializers
        read_data_files
        read_options   # applies this dataset's fields (fragment carries no problem-level keys)
        @dataset.save
        @log << "Imported additional dataset '#{display_name}'"
      end
    ensure
      @base_dir, @dataset, @options = outer_base, outer_dataset, outer_options
    end
  end
```

Notes: `read_options` writes `@problem`-level attrs only for keys present in `@options`; the fragment has none, so it only applies dataset fields to `@dataset`. `warn_mixed_group_weights` is intentionally not called for additional datasets (live-dataset concern). `read_cpp_extras` may re-set the **problem-level** `compilation_type`/`submission_filename` if the additional dataset ships a grader — harmless because those are problem-scoped and identical across a problem's datasets (all datasets share one compilation type); do not try to suppress it.

- [ ] **Step 4: Run — expect PASS (both new tests + the whole file)**

Run: `bin/rails test test/engine/problem_multidataset_test.rb`

- [ ] **Step 5: Rubocop + commit** (no changelog)

```bash
bundle exec rubocop app/engine/problem_importer.rb
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_importer.rb test/engine/problem_multidataset_test.rb -m "feat(import): read additional datasets from datasets/ (non-live, name-matched)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: End-to-end structural round-trip (all datasets)

**Files:**
- Test: `test/engine/problem_multidataset_test.rb`

**Interfaces:**
- Consumes: the full export(all)→import path (T3, T4).

- [ ] **Step 1: Write the round-trip test**

```ruby
  test "export(all) -> import round-trips EVERY dataset field-by-field" do
    src = import_rich("md_rt_src")
    ds2 = Dataset.create!(problem: src, name: "Second", time_limit: 4, memory_limit: 77,
                          score_type: :sum, evaluation_type: :default)
    %w[1-1 2-1].each_with_index do |cn, i|
      tc = Testcase.new(code_name: cn, num: i + 1, group: i + 1, group_name: "g#{i + 1}", weight: (i + 1) * 5)
      tc.inp_file.attach(io: StringIO.new("#{i}\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("#{i}\n"), filename: "a", content_type: "text/plain")
      ds2.testcases << tc
    end
    ds2.save!

    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)
      ProblemImporter.new.import_dataset_from_dir(exported, "md_rt_dst", user: users(:admin))
    end
    dst = Problem.find_by(name: "md_rt_dst").reload

    assert_equal src.datasets.count, dst.datasets.count
    s2 = src.datasets.find_by(name: "Second")
    d2 = dst.datasets.find_by(name: "Second")
    assert d2, "additional dataset present by name"
    %w[time_limit memory_limit score_type evaluation_type].each do |f|
      assert_equal s2.send(f), d2.send(f), "Second##{f} round-trips"
    end
    assert_equal s2.testcases.count, d2.testcases.count
    s2.testcases.order(:num).zip(d2.testcases.order(:num)).each do |a, b|
      %w[code_name num group group_name weight].each { |f| assert_equal a.send(f), b.send(f), "tc##{f}" }
      assert_equal a.inp_file.download, b.inp_file.download
      assert_equal a.ans_file.download, b.ans_file.download
    end
    # live dataset also intact
    assert_equal src.live_dataset.testcases.count, dst.live_dataset.testcases.count
  end
```

- [ ] **Step 2: Run — expect PASS** (all machinery already built)

Run: `bin/rails test test/engine/problem_multidataset_test.rb`
If any assertion fails, that's a real gap in T3/T4 — report it with the failing field; do NOT weaken the assertion.

- [ ] **Step 3: Commit** (no changelog — test only)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit test/engine/problem_multidataset_test.rb -m "test: end-to-end multi-dataset round-trip (every dataset field-by-field)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Operator surface — `Problem#export`, `dump_problems`, rake

**Files:**
- Modify: `app/models/problem.rb`, `app/engine/problem_exporter.rb`
- Create: `lib/tasks/problem_export.rake`
- Test: `test/engine/problem_multidataset_test.rb`

**Interfaces:**
- Consumes: `export_problem_to_dir(..., all_datasets:)` (T3).
- Produces: `Problem#export(all_datasets: false)`. Task 8 (controller) consumes it.

- [ ] **Step 1: Write the failing test**

```ruby
  test "Problem#export forwards all_datasets" do
    p = import_rich("md_pexport")
    Dataset.create!(problem: p, name: "X DS", time_limit: 1, memory_limit: 64, score_type: :sum).tap do |d|
      tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
      tc.inp_file.attach(io: StringIO.new("1\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("1\n"), filename: "a", content_type: "text/plain")
      d.testcases << tc; d.save!
    end
    Dir.mktmpdir do |dump|
      res = p.export(all_datasets: true, base_dir: dump, zip: false)
      assert_equal :ok, res[:status]
      assert File.directory?(File.join(dump, p.name.parameterize, "datasets", "x-ds"))
    end
  end
```

- [ ] **Step 2: Run — expect FAIL** (`Problem#export` doesn't accept `all_datasets`/`base_dir`/`zip`)

- [ ] **Step 3: Implement**

In `app/models/problem.rb`, replace `export`:

```ruby
  # export the problem into the given dir (default: judge dump dir)
  def export(all_datasets: false, base_dir: Rails.root.join('../judge/dump'), zip: true)
    pe = ProblemExporter.new
    pe.export_problem_to_dir(self, base_dir: base_dir, zip: zip, all_datasets: all_datasets)
  end
```

In `app/engine/problem_exporter.rb`, forward `all_datasets` from `dump_problems`:

```ruby
  def self.dump_problems(probs = Problem.available, base_dir = Rails.root.join('../judge/dump'), all_datasets: false)
    probs.each do |p|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: base_dir, all_datasets: all_datasets)
      puts "dump '#{p.name}' to #{base_dir}"
    end
  end
```

Create `lib/tasks/problem_export.rake`:

```ruby
namespace :problems do
  desc 'Export a problem to a zip. Usage: rails "problems:export[<name_or_id>,all]" (2nd arg "all" -> all datasets)'
  task :export, %i[ref scope] => :environment do |_t, args|
    unless args[:ref]
      warn 'Usage: rails "problems:export[<problem name or id>,all]"  (omit "all" for live dataset only)'
      next
    end
    problem = Problem.find_by(id: args[:ref]) || Problem.find_by(name: args[:ref])
    unless problem
      warn "Problem '#{args[:ref]}' not found."
      next
    end
    all = args[:scope].to_s.downcase == 'all'
    res = problem.export(all_datasets: all, zip: true)
    puts "Exported '#{problem.name}' (#{all ? 'all datasets' : 'live dataset only'}) -> #{res[:zip]}"
    puts "  status: #{res[:status]}#{res[:error] ? " (#{res[:error]})" : ''}"
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/engine/problem_multidataset_test.rb`
Also confirm the task loads: `bin/rails -T problems:export`.

- [ ] **Step 5: Rubocop + commit** (no changelog — final task consolidates it)

```bash
bundle exec rubocop app/models/problem.rb app/engine/problem_exporter.rb lib/tasks/problem_export.rake
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add lib/tasks/problem_export.rake
hg commit app/models/problem.rb app/engine/problem_exporter.rb lib/tasks/problem_export.rake test/engine/problem_multidataset_test.rb -m "feat(export): all_datasets on Problem#export + dump_problems + problems:export rake

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Web — download dropdown (live / all)

**Files:**
- Modify: `app/controllers/problems_controller.rb` (`download_archive`), `app/views/problems/edit.html.haml`
- Test: `test/controllers/problems_controller_test.rb`

**Interfaces:**
- Consumes: `Problem#export(all_datasets:)` (T6). Route `download_archive_problem_path` (GET) already exists.

- [ ] **Step 1: Write the failing controller test** (append to `ProblemsImportExportControllerTest`)

```ruby
  test "download_archive with all_datasets=1 exports a zip containing datasets/" do
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(Rails.root.join("test", "problem_examples", "rich").to_s, "dl_all", user: users(:admin))
    p = pi.problem
    Dataset.create!(problem: p, name: "DL Extra", time_limit: 1, memory_limit: 64, score_type: :sum).tap do |d|
      tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
      tc.inp_file.attach(io: StringIO.new("1\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("1\n"), filename: "a", content_type: "text/plain")
      d.testcases << tc; d.save!
    end

    get download_archive_problem_path(p, all_datasets: 1)
    assert_response :success
    Dir.mktmpdir do |d|
      zpath = File.join(d, "out.zip")
      File.binwrite(zpath, response.body)
      names = `unzip -l #{zpath}`
      assert_match(%r{datasets/dl-extra/}, names, "all-datasets zip contains the extra dataset")
    end
  end
```

- [ ] **Step 2: Run — expect FAIL** (plain download has no `datasets/`)

Run: `bin/rails test test/controllers/problems_controller_test.rb`

- [ ] **Step 3: Implement — controller reads the param**

In `problems_controller.rb#download_archive`:

```ruby
  def download_archive
    unless @problem.live_dataset
      redirect_to problems_path, alert: "Problem '#{@problem.name}' has no live dataset to export."
      return
    end
    result = @problem.export(all_datasets: params[:all_datasets].present?)
    send_file result[:zip], type: 'application/x-zip', disposition: 'attachment', filename: result[:zip].basename.to_s
  end
```

- [ ] **Step 4: Implement — the view dropdown**

In `app/views/problems/edit.html.haml`, replace the single download `link_to` (the `download_archive_problem_path(@problem)` button, currently one `= link_to … %span.mi download`) with a Bootstrap dropdown:

```haml
    .dropdown
      %button.btn.btn-sm.bg-white.shadow-sm.border-0.text-secondary.d-inline-flex.align-items-center.justify-content-center{type: 'button', data: {bs_toggle: 'dropdown', bs_title: 'Download Archive'}, 'aria-expanded': 'false'}
        %span.mi download
      %ul.dropdown-menu
        %li= link_to 'Download (live dataset)', download_archive_problem_path(@problem), class: 'dropdown-item'
        %li= link_to 'Download (all datasets)', download_archive_problem_path(@problem, all_datasets: 1), class: 'dropdown-item'
```

(The tooltip lives on the toggle via `data-bs-title` — the parent `data-controller="init-ui-component"` on the toolbar wires it, per the repo's tooltip convention for non-`tooltip` toggles.)

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rails test test/controllers/problems_controller_test.rb`

- [ ] **Step 6: Rubocop + commit** (no changelog — final task)

```bash
bundle exec rubocop app/controllers/problems_controller.rb
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/controllers/problems_controller.rb app/views/problems/edit.html.haml test/controllers/problems_controller_test.rb -m "feat(export): download dropdown for live-only vs all-datasets archive

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Full sweep + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Full minitest suite**

Run: `bin/rails test`
Expected: `0 failures, 0 errors` (4 pre-existing skips). Fix any regression before proceeding; do not skip tests.

- [ ] **Step 2: Rubocop the touched files**

```bash
bundle exec rubocop app/engine/problem_exporter.rb app/engine/problem_importer.rb app/engine/option_const.rb app/models/problem.rb app/controllers/problems_controller.rb lib/tasks/problem_export.rake test/engine/problem_multidataset_test.rb
```
Expected: no offenses (the pre-existing `problem.rb` `helpers_cost` pair may remain — report it as pre-existing, don't fix).

- [ ] **Step 3: CHANGELOG bullet** under `## [Unreleased]` → `### Added`:

```markdown
- **Multi-dataset problem export/import** — a problem's non-live datasets can now
  be included in its export archive ("Download (all datasets)" on the problem
  page, `Problem#export(all_datasets: true)`, or `rails "problems:export[name,all]"`),
  and are re-imported as additional (non-live) datasets. The zip format is a
  backward-compatible superset: old archives import unchanged, and the default
  "live dataset only" export is byte-compatible with previous versions.
```

- [ ] **Step 4: Commit**

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit CHANGELOG.md -m "changelog: multi-dataset export/import

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
