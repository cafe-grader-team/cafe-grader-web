# Package 1 — Harden Trusted Problem Import/Export: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the audited bugs in `ProblemImporter`/`ProblemExporter`, make export a true inverse of the trusted import (portable-package contract), and pin both with characterization + round-trip tests.

**Architecture:** No structural changes — targeted in-place fixes to `app/engine/problem_importer.rb`, `app/engine/problem_exporter.rb`, `app/engine/option_const.rb`, `problems_controller.rb`, `scorer.rb`. Tests drive every fix (red→green). Spec: `doc/problem-import-export-design-2026-07-14.md` (§Package 1).

**Tech Stack:** Ruby 3.4.4 / Rails 8.0, minitest (`ActiveSupport::TestCase`, `ActionDispatch::IntegrationTest`), fixtures in `test/fixtures/` (users: `admin`/`john`/`mary`), ActiveStorage `:test` service, Mercurial.

## Global Constraints

- **VCS is Mercurial.** Before EVERY commit run `hg log -r . --template '{activebookmark}\n'` — it MUST print `master`. If it prints `chula_cp`, run `hg update master` first.
- **Name explicit files in every `hg commit`** (the repo often has unrelated dirty files). End commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **CHANGELOG.md in the same commit** as each user/operator-facing change: add the bullet given in the task under `## [Unreleased]` (create `### Fixed` / `### Added` / `### Security` subsections as needed, in that order: Added, Changed, Fixed, Security). Tasks marked "no changelog" skip this.
- Run tests with `bin/rails test <path>`. Do NOT run `bin/rails check` per task (slow; RSpec+swagger) — full sweep is Task 12.
- The importer is trusted production code: make ONLY the changes specified. No drive-by refactors, no renames beyond those specified.
- New behavior must keep old zips importing identically (config keys are optional; absent key = old behavior, except the `markdown` legacy default specified in Task 5).

## File Structure

- `test/engine/problem_import_test.rb` — **create**: characterization + importer fix tests (Tasks 1–4, 6, 7)
- `test/engine/problem_round_trip_test.rb` — **create**: export + round-trip parity tests (Task 5)
- `test/problem_examples/rich/` — **create**: full-surface fixture (Task 5)
- `test/controllers/problems_controller_test.rb` — **create**: controller guard/auth tests (Tasks 8–10)
- `app/engine/option_const.rb` — **modify**: shared field lists, `data_files` dir, statement/description filenames
- `app/engine/problem_importer.rb` — **modify**: fixes
- `app/engine/problem_exporter.rb` — **modify**: fixes
- `app/controllers/problems_controller.rb` — **modify**: guards + auth + user pass-through
- `app/engine/scorer.rb`, `doc/dataset-scoring-and-evaluation.md` — **modify**: min-weight wording
- `app/models/problem.rb` — **modify**: delete dead method
- `CHANGELOG.md` — **modify**: per-task bullets

---

### Task 1: Import characterization baseline (fibo fixture)

**Files:**
- Test (create): `test/engine/problem_import_test.rb`

**Interfaces:**
- Produces: `import_example(subdir, name, **opts)` helper used by Tasks 2–4, 6, 7. Signature: `import_example(dir_path_string, problem_name_string, **kwargs_forwarded_to_import_dataset_from_dir) → ProblemImporter`.

This test pins current-correct behavior; it should PASS immediately.

- [ ] **Step 1: Write the characterization test**

```ruby
# test/engine/problem_import_test.rb
require "test_helper"
require "tmpdir"

class ProblemImportTest < ActiveSupport::TestCase
  EXAMPLES = Rails.root.join("test", "problem_examples")

  # Import a problem-example directory (no zip involved) and return the importer.
  def import_example(dir, name, **opts)
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(dir.to_s, name, **opts)
    pi
  end

  test "fibo example imports with fields from config.yml" do
    pi = import_example(EXAMPLES.join("fibo"), "fibo_test", do_solutions: false)
    problem = pi.problem
    ds = pi.dataset

    assert_equal "fibo_test", problem.name
    assert_equal "Fibonacci Number", problem.full_name   # from config.yml
    assert_equal "batch", problem.task_type
    assert_equal "self_contained", problem.compilation_type
    assert_equal %w[Book DP], problem.tags.pluck(:name).sort
    assert problem.statement.attached?, "statement.pdf should attach"

    assert_equal 1.0, ds.time_limit.to_f
    assert_equal 512, ds.memory_limit
    assert_equal "sum", ds.score_type
    assert_equal "default", ds.evaluation_type
    assert_equal 8, ds.testcases.count
    # config.yml assigns each testcase its own group with weight 10
    assert_equal (1..8).to_a, ds.testcases.order(:num).pluck(:group)
    assert_equal [10] * 8, ds.testcases.order(:num).pluck(:weight)
    tc1 = ds.testcases.find_by(code_name: "1")
    # content identical to the fixture file (importer only strips \r)
    assert_equal File.read(EXAMPLES.join("fibo", "testcases", "1.in")),
                 tc1.inp_file.download
  end
end
```

- [ ] **Step 2: Run — expect PASS**

Run: `bin/rails test test/engine/problem_import_test.rb`
Expected: `1 runs, ... 0 failures, 0 errors`. If it fails, STOP — the baseline
assumption is wrong; investigate before continuing (do not "fix" the test to
match without understanding).

- [ ] **Step 3: Commit** (no changelog — test only)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add test/engine/problem_import_test.rb
hg commit test/engine/problem_import_test.rb -m "test: characterization baseline for ProblemImporter (fibo example)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Fix dead `code_name_regex` variable

**Files:**
- Modify: `app/engine/problem_importer.rb:29-31` and `:47-49`
- Test: `test/engine/problem_import_test.rb`

- [ ] **Step 1: Write the failing test** (append inside the class)

```ruby
  test "code_name_regex extracts codename from wildcard match" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "case_1.in"), "in1\n")
      File.write(File.join(dir, "case_1.sol"), "out1\n")
      pi = import_example(dir, "cnr_test", do_solutions: false,
                          code_name_regex: /_(\d+)\z/)
      assert_equal ["1"], pi.dataset.testcases.pluck(:code_name),
                   "code_name_regex should reduce 'case_1' to '1'"
    end
  end
```

- [ ] **Step 2: Run — expect FAIL** (`code_name` is `"case_1"`: the regex result is discarded)

Run: `bin/rails test test/engine/problem_import_test.rb`

- [ ] **Step 3: Fix both occurrences**

In `read_testcase`, the input loop currently reads:

```ruby
      # parse codename according to regex
      codename_mc = name.match code_name_regex
      codename = mc[1] if mc
```

Change to (in BOTH the input_pattern loop and the sol_pattern loop):

```ruby
      # parse codename according to regex
      codename_mc = name.match code_name_regex
      codename = codename_mc[1] if codename_mc
```

- [ ] **Step 4: Run — expect PASS (both tests)**

- [ ] **Step 5: Commit with changelog**

CHANGELOG bullet under `[Unreleased]` → `### Fixed`:

```markdown
- **Problem import: `code_name_regex` now actually applies** — the custom
  code-name extraction regex accepted by `ProblemImporter` was parsed but its
  result discarded; testcase code names always fell back to the raw wildcard
  match.
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_importer.rb test/engine/problem_import_test.rb CHANGELOG.md -m "fix: apply code_name_regex in testcase import (dead-variable bug)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Model-solution import — filename split, `:model` tag, `user:` kwarg

**Files:**
- Modify: `app/engine/problem_importer.rb` (`read_solutions`, `import_dataset_from_dir` signature)
- Modify: `app/controllers/problems_controller.rb` (`do_import` call site)
- Test: `test/engine/problem_import_test.rb`

**Interfaces:**
- Produces: `import_dataset_from_dir(..., user: nil)` — new optional kwarg; `read_solutions(user:)`. Task 5's round-trip test and the controller rely on these names.

- [ ] **Step 1: Write the failing test**

```ruby
  test "model solutions import with correct filename, model tag, and user" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "1.in"), "1\n")
      File.write(File.join(dir, "1.sol"), "1\n")
      sol_dir = File.join(dir, "model_solutions")
      FileUtils.mkdir_p(sol_dir)
      File.write(File.join(sol_dir, "cpp_fibo.cpp"), "int main(){}\n")

      pi = import_example(dir, "sol_test", user: users(:admin))
      subs = pi.problem.submissions
      assert_equal 1, subs.count, "model solution should create one submission"
      sub = subs.first
      assert_equal "fibo.cpp", sub.source_filename
      assert_equal "cpp", sub.language.name
      assert sub.tag_model?, "imported solution must be tagged :model"
      assert_equal users(:admin), sub.user
    end
  end
```

- [ ] **Step 2: Run — expect FAIL** (`source_filename` is `"p_fibo.cpp"`, tag is default, kwarg doesn't exist → ArgumentError is also an acceptable first failure)

- [ ] **Step 3: Implement**

In `import_dataset_from_dir`, add the kwarg (after `do_initializers: true`):

```ruby
    do_initializers: true,
    user: nil             # attributed owner of imported model solutions
```

and change the call `read_solutions if do_solutions` to:

```ruby
    read_solutions(user: user) if do_solutions
```

Replace `read_solutions` body's submission construction:

```ruby
  def read_solutions(user: nil)
    user ||= User.first
    solutions_dir = @options[OptionConst::YAML_KEY[:dir][:model_sols]] || OptionConst::DEFAULT[:dir][:model_sols]
    pattern = build_glob('*', recursive: true, path: solutions_dir)
    Dir.glob(pattern).each do |fn|
      pn = Pathname.new(fn)
      next if pn.directory?

      @log << "Found a model solution file [#{fn}]"
      # filename convention: <language>_<original_filename>, e.g. cpp_fibo.cpp
      lang_name, sep, source_name = pn.basename.to_s.partition('_')
      if sep.empty?
        @log << "  ERROR: solution filename '#{pn.basename}' has no <lang>_ prefix; skipped"
        next
      end

      language = Language.where(name: lang_name).first
      sub =  Submission.new(user: user,
                            problem: @problem,
                            submitted_at: Time.zone.now,
                            language: language,
                            source_filename: source_name,
                            tag: :model)
      sub.source = File.open(fn, 'r:UTF-8', &:read)
      sub.source.encode!('UTF-8', 'UTF-8', invalid: :replace, replace: '')

      if sub.save
        sub.add_judge_job
      else
        @log << "  ERROR: could not save solution: #{sub.errors.full_messages.join('; ')}"
      end
    end
  end
```

(The `managers_fn = {}` local in the old body was unused — it is gone here.)

In `problems_controller.rb#do_import`, add `user: @current_user` to the
`pi.import_dataset_from_dir(...)` call:

```ruby
    pi.import_dataset_from_dir(extracted_path, params[:problem][:name],
      full_name: params[:problem][:full_name],
      input_pattern: params[:problem][:input_pattern],
      sol_pattern: params[:problem][:sol_pattern],
      delete_existing: params[:problem][:replace] == '1',
      memory_limit: memory_limit,
      time_limit: time_limit,
      user: @current_user,
    )
```

- [ ] **Step 4: Run — expect PASS (all tests in file)**

- [ ] **Step 5: Commit with changelog**

CHANGELOG bullet → `### Fixed`:

```markdown
- **Problem import: model solutions survive round-trips** — imported model
  solutions had garbled source filenames (`cpp_fibo.cpp` → `p_fibo.cpp`), were
  not tagged as model solutions (so the *next* export silently dropped them),
  and were attributed to an arbitrary user; they are now split on the first
  `_`, tagged `:model`, and owned by the importing user.
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_importer.rb app/controllers/problems_controller.rb test/engine/problem_import_test.rb CHANGELOG.md -m "fix: model-solution import filename/tag/ownership

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Blank `full_name` falls back to `name`

**Files:**
- Modify: `app/engine/problem_importer.rb` (`import_dataset_from_dir`)
- Test: `test/engine/problem_import_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  test "blank full_name falls back to problem name" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "1.in"), "1\n")
      File.write(File.join(dir, "1.sol"), "1\n")
      pi = import_example(dir, "fn_test", full_name: "", do_solutions: false)
      assert_equal "fn_test", pi.problem.full_name
    end
  end
```

- [ ] **Step 2: Run — expect FAIL** (`full_name` is `""`)

- [ ] **Step 3: Implement** — in `import_dataset_from_dir`, change

```ruby
    @problem.full_name = full_name
```

to

```ruby
    @problem.full_name = full_name.presence || name
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit with changelog** → `### Fixed`:

```markdown
- **Problem import: empty "Full name" no longer blanks the title** — it now
  falls back to the short name (a `config.yml` `full_name` still wins).
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_importer.rb test/engine/problem_import_test.rb CHANGELOG.md -m "fix: blank full_name falls back to problem name on import

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Round-trip parity — shared field lists, description/markdown, score_param, data_files, export typos

**Files:**
- Create: `test/problem_examples/rich/` (fixture)
- Create: `test/engine/problem_round_trip_test.rb`
- Modify: `app/engine/option_const.rb`
- Modify: `app/engine/problem_importer.rb`
- Modify: `app/engine/problem_exporter.rb`

**Interfaces:**
- Produces: `OptionConst::PROBLEM_OPTION_FIELDS`, `OptionConst::DATASET_OPTION_FIELDS` (arrays of symbols) — the single source of truth both engines read. `OptionConst::DEFAULT[:dir][:data_files] == 'data_files'`, `OptionConst::DEFAULT[:file][:statement] == 'statement.pdf'`, `OptionConst::DEFAULT[:file][:description] == 'description.md'`, `OptionConst::YAML_KEY[:dir][:data_files] == :data_files_dir`.
- Consumes: `user:` kwarg from Task 3.

- [ ] **Step 1: Create the rich fixture**

```bash
mkdir -p test/problem_examples/rich/{testcases,checker,managers,initializers,data_files,attachment,model_solutions}
```

Create these files (exact content):

`test/problem_examples/rich/testcases/1-1.in` → `1 1\n` · `1-1.sol` → `2\n`
`test/problem_examples/rich/testcases/1-2.in` → `2 2\n` · `1-2.sol` → `4\n`
`test/problem_examples/rich/testcases/2-1.in` → `3 3\n` · `2-1.sol` → `6\n`
`test/problem_examples/rich/checker/checker` → `#!/bin/sh\necho 1\n`
`test/problem_examples/rich/managers/grader.cpp` → `int main(){return 0;}\n`
`test/problem_examples/rich/managers/helper.h` → `#pragma once\n`
`test/problem_examples/rich/initializers/init.sql` → `SELECT 1;\n`
`test/problem_examples/rich/data_files/lookup.txt` → `42\n`
`test/problem_examples/rich/attachment/starter.txt` → `starter kit\n`
`test/problem_examples/rich/model_solutions/cpp_rich.cpp` → `int main(){}\n`
`test/problem_examples/rich/statement.pdf` → `%PDF-1.4\n%%EOF\n`
`test/problem_examples/rich/description.md` → `# Rich\nExtra **markdown** description.\n`

`test/problem_examples/rich/config.yml`:

```yaml
---
name: rich
full_name: Rich Example
submission_filename: student.h
task_type: batch
compilation_type: with_managers
permitted_lang: cpp python
time_limit: 2.5
memory_limit: 256
score_type: group_min
evaluation_type: custom_cms
score_param: 'p=1'
main_filename: grader.cpp
initializer_filename: init.sql
markdown: true
tags:
- roundtrip
testcases:
  1-1: { group: 1, group_name: 'easy', weight: 30 }
  1-2: { group: 1, group_name: 'easy', weight: 30 }
  2-1: { group: 2, group_name: 'hard', weight: 40 }
```

- [ ] **Step 2: Write the round-trip test**

```ruby
# test/engine/problem_round_trip_test.rb
require "test_helper"
require "tmpdir"

class ProblemRoundTripTest < ActiveSupport::TestCase
  EXAMPLES = Rails.root.join("test", "problem_examples")

  PROBLEM_FIELDS = %w[full_name description markdown submission_filename
                      task_type compilation_type permitted_lang].freeze
  DATASET_FIELDS = %w[time_limit memory_limit score_type evaluation_type
                      score_param main_filename initializer_filename].freeze
  TESTCASE_FIELDS = %w[code_name num group group_name weight].freeze

  def import_dir(dir, name)
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(dir.to_s, name, user: users(:admin))
    pi.problem.reload
  end

  test "import -> export -> re-import preserves the portable package" do
    original = import_dir(EXAMPLES.join("rich"), "rt_original")

    Dir.mktmpdir do |dump|
      pe = ProblemExporter.new
      pe.export_problem_to_dir(original, base_dir: dump, zip: false)
      exported_dir = File.join(dump, original.name.parameterize)

      copy = import_dir(exported_dir, "rt_copy")

      PROBLEM_FIELDS.each do |f|
        assert_equal original.send(f), copy.send(f), "Problem##{f} lost in round-trip"
      end
      assert_equal original.tags.pluck(:name).sort, copy.tags.pluck(:name).sort
      assert_equal original.statement.download, copy.statement.download
      assert_equal original.attachment.download, copy.attachment.download

      ods, cds = original.live_dataset, copy.live_dataset
      DATASET_FIELDS.each do |f|
        assert_equal ods.send(f), cds.send(f), "Dataset##{f} lost in round-trip"
      end
      assert_equal ods.checker.download, cds.checker.download
      %w[managers initializers data_files].each do |coll|
        assert_equal ods.send(coll).map { |a| a.filename.to_s }.sort,
                     cds.send(coll).map { |a| a.filename.to_s }.sort,
                     "Dataset##{coll} filenames lost in round-trip"
      end

      assert_equal ods.testcases.count, cds.testcases.count
      ods.testcases.order(:num).zip(cds.testcases.order(:num)).each do |o, c|
        TESTCASE_FIELDS.each { |f| assert_equal o.send(f), c.send(f), "Testcase##{f} differs (#{o.code_name})" }
        assert_equal o.inp_file.download, c.inp_file.download
        assert_equal o.ans_file.download, c.ans_file.download
      end

      # model solutions re-exportable: copy has a :model-tagged submission
      assert_equal 1, copy.submissions.where(tag: :model).count
    end
  end

  test "dump_problems does not crash (zip default typo)" do
    import_dir(EXAMPLES.join("rich"), "rt_dump")
    Dir.mktmpdir do |dump|
      assert_nothing_raised do
        ProblemExporter.dump_problems(Problem.where(name: "rt_dump"), dump)
      end
    end
  end

  test "exported statement file is named statement.pdf" do
    p = import_dir(EXAMPLES.join("rich"), "rt_stmt")
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: dump, zip: false)
      assert File.exist?(File.join(dump, p.name.parameterize, "statement.pdf")),
             "expected statement.pdf in the exported package"
    end
  end
end
```

Note: the exported `ds_name` config key is deliberately NOT applied on import
(dataset display names are auto-generated locally; existing behavior kept) —
that's why `DATASET_FIELDS` excludes `name`.

- [ ] **Step 3: Run — expect FAIL** on `description`, `markdown`, `score_param`, `data_files`, `NameError (fasle)`, and `statement.pdf`.

Run: `bin/rails test test/engine/problem_round_trip_test.rb`

- [ ] **Step 4: Implement — `option_const.rb`**

Replace the whole module body with:

```ruby
module OptionConst
  # YAML default options value
  DEFAULT = {
    dir: {
      testcases: 'testcases',
      attachment: 'attachment',
      checker: 'checker',
      managers: 'managers',
      model_sols: 'model_solutions',
      initializers: 'initializers',
      data_files: 'data_files'
    },
    file: {
      checker: 'checker',
      statement: 'statement.pdf',
      description: 'description.md'
    }
  }

  # the config filename
  YAML_FILENAME = 'config.yml'

  # these are keys of the Option hash, MUST BE SYMBOL
  YAML_KEY = {
    dir: {
      testcases: :testcases_dir,
      attachment: :attachment_dir,
      checker: :checker_dir,
      managers: :managers_dir,
      model_sols: :solutions_dir,
      initializers: :initializers_dir,
      data_files: :data_files_dir
    },
    ds_name: :ds_name,
    tags: :tags,
    checker: :checker,
    managers_pattern: :managers_pattern,
    testcases: :testcases,
    testcases_pattern: :testcases_pattern,
    initializer: :initializer
  }

  # Problem / live-Dataset attributes carried in config.yml.
  # Single source of truth for BOTH ProblemImporter#read_options and
  # ProblemExporter#export_options — do not redefine lists there.
  PROBLEM_OPTION_FIELDS = %i[full_name submission_filename task_type
                             compilation_type permitted_lang markdown]
  DATASET_OPTION_FIELDS = %i[time_limit memory_limit score_type
                             evaluation_type score_param main_filename
                             initializer_filename]
end
```

- [ ] **Step 5: Implement — importer**

In `read_options`, replace the two hardcoded lists:

```ruby
    p_options = OptionConst::PROBLEM_OPTION_FIELDS
    p_options.each do |opt|
```
```ruby
    d_options = OptionConst::DATASET_OPTION_FIELDS
    d_options.each do |opt|
```

(delete the old inline `%i[...]` arrays and their `MUST MATCH` comments).

In `read_statement`, replace the markdown-description block:

```ruby
    # additional description
    md, fn = get_content_of_first_match('*.md')
    if md
      @problem.description = md
      # config.yml's :markdown (applied later in read_options) wins;
      # legacy packages without the key: a .md present means markdown
      @problem.markdown = true unless @options.has_key?(:markdown)
      @problem.save
      @log << "Found addtional Markdown file [#{fn}]"
      @got << fn
    end
```

Add `read_data_files` (after `read_initializers`):

```ruby
  def read_data_files
    path = @options[OptionConst::YAML_KEY[:dir][:data_files]] || OptionConst::DEFAULT[:dir][:data_files]
    pattern = build_glob('*', path: path)
    seen = {}
    Dir.glob(pattern).each do |fn|
      pn = Pathname.new(fn)
      next if pn.directory?

      @log << "Found a data file [#{fn}]"
      @got << fn
      basename = pn.basename
      if seen.has_key? basename
        @log << "  ERROR: multiple data files of the same name #{basename}"
      else
        seen[basename] = true
        @dataset.data_files.each { |f| f.purge if f.filename == basename }
        @dataset.reload
        @dataset.data_files.attach(io: File.open(fn), filename: basename)
      end
    end
    @dataset.save
  end
```

In `import_dataset_from_dir`: add kwarg `do_data_files: true,` (next to
`do_initializers: true`) and call it next to the initializers call:

```ruby
    read_initializers if do_initializers
    read_data_files if do_data_files
```

- [ ] **Step 6: Implement — exporter**

In `export_options`, replace the two lists (keep the `[:name]` extra and the
BigDecimal coercion):

```ruby
    p_options = [:name] + OptionConst::PROBLEM_OPTION_FIELDS
```
```ruby
    d_options = OptionConst::DATASET_OPTION_FIELDS
```

Still in `export_options`, after the `d_options` loop add (booleans are
`blank?`-skipped by the generic loop, so export `markdown` explicitly):

```ruby
    # markdown is boolean; export explicitly whenever a description exists
    @options[:markdown] = !!@problem.markdown if @problem.description.present?
```

and register the data_files dir alongside the other dir keys:

```ruby
    @options[OptionConst::YAML_KEY[:dir][:data_files]] = OptionConst::DEFAULT[:dir][:data_files]
```

Add the two new export methods (after `export_initializers`):

```ruby
  def export_description
    return if @problem.description.blank?
    File.write(@main_dir + OptionConst::DEFAULT[:file][:description], @problem.description)
  end

  def export_data_files
    @data_files_dir = @main_dir + OptionConst::DEFAULT[:dir][:data_files]
    @data_files_dir.mkpath
    @ds.data_files.each do |df|
      filename = @data_files_dir + df.filename.to_s
      File.open(filename, 'w:ASCII-8BIT') { |f| df.download { |chunk| f.write chunk } }
    end
  end
```

In `export_problem_to_dir`: fix the typo'd default and call the new exports —

```ruby
  def export_problem_to_dir(problem, base_dir: Rails.root.join('../judge/dump'), zip: false)
```

```ruby
    export_pdf
    export_attachment
    export_description
    export_testcases
    export_managers_checker
    export_initializers
    export_data_files
    export_options
    export_solutions
```

- [ ] **Step 7: Run — expect PASS (all three tests)**

Run: `bin/rails test test/engine/problem_round_trip_test.rb test/engine/problem_import_test.rb`
Expected: `0 failures, 0 errors` (import tests must still pass — old zips see
identical behavior; every new config key is optional).

- [ ] **Step 8: Commit with changelog**

CHANGELOG bullets → `### Fixed`:

```markdown
- **Problem export now round-trips everything the author created** — the
  markdown description, `markdown` flag, `score_param`, and dataset data
  files were silently dropped by export (or never imported); an exported zip
  re-imports field-identical. `ProblemExporter.dump_problems` (console bulk
  export) no longer crashes on a typo'd default, and the exported statement
  is named `statement.pdf` (was `statment.pdf`).
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add test/engine/problem_round_trip_test.rb test/problem_examples/rich
hg commit test/engine/problem_round_trip_test.rb test/problem_examples/rich app/engine/option_const.rb app/engine/problem_importer.rb app/engine/problem_exporter.rb CHANGELOG.md -m "fix: export/import round-trip parity (description, markdown, score_param, data_files, typos)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Mixed group-weight warning on import

**Files:**
- Modify: `app/engine/problem_importer.rb`
- Test: `test/engine/problem_import_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  test "group_min with mixed weights inside a group logs a warning" do
    Dir.mktmpdir do |dir|
      %w[1-1 1-2].each do |cn|
        File.write(File.join(dir, "#{cn}.in"), "x\n")
        File.write(File.join(dir, "#{cn}.sol"), "y\n")
      end
      File.write(File.join(dir, "config.yml"), <<~YAML)
        ---
        score_type: group_min
        testcases:
          1-1: { group: 1, group_name: 'g1', weight: 10 }
          1-2: { group: 1, group_name: 'g1', weight: 20 }
      YAML
      pi = import_example(dir, "mixed_w", do_solutions: false)
      assert pi.log.any? { |l| l =~ /WARNING.*group 1.*mixed/ },
             "expected mixed-weight warning, log was: #{pi.log.inspect}"
    end
  end
```

- [ ] **Step 2: Run — expect FAIL** (no warning emitted)

- [ ] **Step 3: Implement** — add to `ProblemImporter`:

```ruby
  # CMS semantics: a group has ONE weight; scorer.rb's group_min uses the
  # minimum weight found in the group. Mixed weights are an authoring error.
  def warn_mixed_group_weights
    return unless @dataset.st_group_min?
    @dataset.testcases.group(:group).having('COUNT(DISTINCT weight) > 1')
            .count.each_key do |g|
      @log << "WARNING: group #{g} has mixed testcase weights; group_min uses one weight per group (the minimum). Fix the weights in the package."
    end
  end
```

and call it in `import_dataset_from_dir` right after
`read_options # options is put to last...`:

```ruby
    read_options # options is put to last, it will override any defaults
    warn_mixed_group_weights
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit with changelog** → `### Added`:

```markdown
- **Problem import warns when a `group_min` group has mixed testcase
  weights** — group-min scoring uses one weight per group (the minimum);
  heterogeneous weights inside a group are an authoring error.
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_importer.rb test/engine/problem_import_test.rb CHANGELOG.md -m "feat: warn on mixed group weights during group_min import

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Shell safety — argv exec, parameterized extraction dir, containment check

**Files:**
- Modify: `app/engine/problem_importer.rb` (`unzip_to_dir`, new `validate_containment!`)
- Modify: `app/engine/problem_exporter.rb` (zip command)
- Test: `test/engine/problem_import_test.rb`

**Interfaces:**
- Produces: `ProblemImporter#validate_containment!(destination) → true/false` (false = escape found, `@errors` populated, extraction dir removed). `unzip_to_dir` signature unchanged.

- [ ] **Step 1: Write the failing tests**

```ruby
  test "unzip_to_dir survives hostile problem names" do
    zip = Rails.root.join("test", "problem_examples", "fibo_minimal.zip")
    Dir.mktmpdir do |raw|
      pi = ProblemImporter.new
      dest = pi.unzip_to_dir(zip.to_s, "evil; touch /tmp/pwned name", raw)
      assert dest, "extraction should succeed, errors: #{pi.errors.inspect}"
      assert File.directory?(dest)
      assert_match(/\Aevil-touch-tmp-pwned-name/, File.basename(dest),
                   "destination dir must be parameterized")
    end
  end

  test "validate_containment! rejects symlink escapes" do
    Dir.mktmpdir do |raw|
      dest = File.join(raw, "pkg")
      FileUtils.mkdir_p(dest)
      File.symlink("/etc", File.join(dest, "escape"))
      pi = ProblemImporter.new
      refute pi.validate_containment!(dest)
      assert pi.errors.any? { |e| e =~ /escape/i }
      refute File.exist?(dest), "offending extraction dir must be removed"
    end
  end
```

- [ ] **Step 2: Run — expect FAIL** (hostile name: unzip exits non-zero because the shell mangles the destination; `validate_containment!` undefined)

- [ ] **Step 3: Implement** — replace `unzip_to_dir` and add the validator:

```ruby
  def unzip_to_dir(file, name, dir)
    Pathname.new(dir).mkpath
    safe_name = name.to_s.parameterize
    safe_name = 'problem' if safe_name.blank?
    pn  = Pathname.new(dir) + safe_name
    num = 1
    while pn.exist?
      pn  = Pathname.new(dir) + "#{safe_name}.#{num}"
      num += 1
    end

    destination = pn.cleanpath

    out, err, status = Open3.capture3('unzip', file.to_s, '-d', destination.to_s)
    unless status.exitstatus == 0
      @errors << err
      return nil
    end
    return nil unless validate_containment!(destination)
    destination
  end

  # Zip-slip defense: every extracted entry (and every symlink target) must
  # resolve inside the extraction dir, regardless of unzip version behavior.
  def validate_containment!(destination)
    base = File.realpath(destination.to_s)
    Dir.glob("#{destination}/**/*", File::FNM_DOTMATCH).each do |entry|
      next if ['.', '..'].include?(File.basename(entry))
      resolved = File.symlink?(entry) ? File.expand_path(File.readlink(entry), File.dirname(entry))
                                      : (File.realpath(entry) rescue nil)
      next if resolved&.start_with?("#{base}/") || resolved == base
      @errors << "Archive entry '#{File.basename(entry)}' escapes the extraction directory; import aborted"
      FileUtils.rm_rf(destination)
      return false
    end
    true
  end
```

In `problem_exporter.rb#export_problem_to_dir`, replace the zip invocation:

```ruby
      out, err, status = Open3.capture3('zip', "../#{zip_name}", '-r', '.', chdir: @main_dir.to_s)
```

and change the status check just below it from `if status != 0` to the
clearer idiomatic form (behavior-equivalent — `Process::Status#==` does
compare against integers, but don't rely on it):

```ruby
      if !status.success?
```

- [ ] **Step 4: Run — expect PASS**; also re-run round-trip file:

Run: `bin/rails test test/engine/problem_import_test.rb test/engine/problem_round_trip_test.rb`

- [ ] **Step 5: Verify the zip path end-to-end** (zip: true now exercises the argv form):

```bash
bin/rails runner 'p = Problem.find_by(name: "ex02e1_fibo") || Problem.joins(:live_dataset).first; r = p.export; puts r[:status]; puts r[:zip]'
```
Expected: `ok` and a zip path; `unzip -l <path>` lists `config.yml` etc.

- [ ] **Step 6: Commit with changelog** → `### Security`:

```markdown
- **Problem import/export no longer builds shell strings** — unzip/zip run
  with argv-style exec (a hostile problem name could previously inject shell
  syntax), extraction directories are derived via `parameterize`, and a
  containment check rejects archives whose entries or symlinks escape the
  extraction directory (zip-slip).
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/problem_importer.rb app/engine/problem_exporter.rb test/engine/problem_import_test.rb CHANGELOG.md -m "security: argv exec + parameterized dirs + zip-slip containment for import/export

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: `import_testcases` — invalid replace-target errors; attachment untouched

**Files:**
- Create: `test/controllers/problems_controller_test.rb`
- Modify: `app/controllers/problems_controller.rb` (`import_testcases`)

**Interfaces:**
- Consumes: routes `import_testcases_problem_path(problem)` (POST), `sign_in_as(login, password)` from `test_helper.rb`; fixture users `admin`/`admin`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/controllers/problems_controller_test.rb
require "test_helper"

class ProblemsControllerTest < ActionDispatch::IntegrationTest
  EXAMPLES = Rails.root.join("test", "problem_examples")

  setup do
    sign_in_as("admin", "admin")
    # a real problem to import testcases into
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(EXAMPLES.join("fibo_minimal").to_s, "pct_fibo",
                               do_solutions: false)
    @problem = pi.problem
  end

  test "import_testcases replace with invalid dataset id errors instead of creating a dataset" do
    assert_no_difference "Dataset.count" do
      post import_testcases_problem_path(@problem), params: {
        import: { file: fixture_zip, target: "replace", dataset: 0,
                  input_pattern: "*.in", sol_pattern: "*.sol" }
      }
    end
    assert_response :success
    assert_match(/not found/i, response.body)
  end

  test "import_testcases does not touch the problem attachment" do
    @problem.attachment.attach(io: StringIO.new("keep me"), filename: "keep.txt")
    @problem.save
    post import_testcases_problem_path(@problem), params: {
      import: { file: fixture_zip, target: "new",
                input_pattern: "*.in", sol_pattern: "*.sol" }
    }
    @problem.reload
    assert_equal "keep me", @problem.attachment.download
  end

  private

  # A zip whose root has 9.in, 9.sol, and attachment/sneaky.txt — the
  # attachment/ dir lets the second test prove the testcases-only flow
  # leaves the problem attachment alone.
  def fixture_zip
    @fixture_zip ||= begin
      dir = Dir.mktmpdir
      File.write(File.join(dir, "9.in"), "9\n")
      File.write(File.join(dir, "9.sol"), "34\n")
      att = File.join(dir, "attachment")
      FileUtils.mkdir_p(att)
      File.write(File.join(att, "sneaky.txt"), "should not import\n")
      system("zip", "-q", "-r", "tc.zip", ".", "-x", "tc.zip", chdir: dir) or raise "zip failed"
      Rack::Test::UploadedFile.new(File.join(dir, "tc.zip"), "application/zip")
    end
  end
end
```

Requires `require "tmpdir"` under `require "test_helper"` at the top of this
new file.

- [ ] **Step 2: Run — expect FAIL** (test 1: a new dataset is silently created; test 2: attachment replaced by `sneaky.txt`)

Run: `bin/rails test test/controllers/problems_controller_test.rb`

- [ ] **Step 3: Implement** — in `import_testcases`:

```ruby
    if replacing
      @dataset = @problem.datasets.where(id: params[:import][:dataset]).first
      unless @dataset
        @errors = ['The dataset to replace was not found']
        render :import and return
      end
      WorkerDataset.where(dataset_id: @dataset.id).delete_all
    end
```

and add `do_attachment: false,` to its `pi.import_dataset_from_dir(...)` call:

```ruby
    pi.import_dataset_from_dir(extracted_path, @problem.name,
                                full_name: @problem.full_name,
                                input_pattern: params[:import][:input_pattern],
                                sol_pattern: params[:import][:sol_pattern],
                                dataset: @dataset,
                                do_statement: false,
                                do_checker: false,
                                do_cpp_extras: false,
                                do_solutions: false,
                                do_attachment: false
                              )
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit with changelog** → `### Fixed`:

```markdown
- **"Import testcases" is stricter** — replacing into a dataset that no longer
  exists now errors instead of silently creating a new dataset, and the
  testcases-only flow no longer overwrites the problem's public attachment
  when the uploaded zip happens to contain an `attachment/` directory.
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add test/controllers/problems_controller_test.rb
hg commit test/controllers/problems_controller_test.rb app/controllers/problems_controller.rb CHANGELOG.md -m "fix: import_testcases replace-target guard + attachment isolation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: `do_import` cannot overwrite a problem you can't edit

**Files:**
- Modify: `app/controllers/problems_controller.rb` (`do_import`)
- Test: `test/controllers/problems_controller_test.rb`

**Interfaces:**
- Consumes: `User#problems_for_action(:edit)` (existing model authorization — do NOT invent new checks), `GroupUser` role enum (`editor: 2`).

- [ ] **Step 1: Write the failing tests** (append to `ProblemsControllerTest`)

```ruby
  test "group editor cannot overwrite an existing problem they cannot edit" do
    # @problem ('pct_fibo') exists and belongs to no group mary can edit
    group = Group.create!(name: "mary's group", enabled: true)
    GroupUser.create!(group: group, user: users(:mary), role: :editor)
    sign_in_as("mary", "mary")

    assert_no_difference -> { @problem.live_dataset.testcases.count } do
      post do_import_problems_path, params: {
        problem: { name: @problem.name, full_name: "Takeover",
                   file: fixture_zip, groups: group.id,
                   input_pattern: "*.in", sol_pattern: "*.sol",
                   time_limit: 1, memory_limit: 64 }
      }
    end
    assert_match(/already exists/i, response.body)
    assert_not_equal "Takeover", @problem.reload.full_name
  end

  test "admin can still re-import over an existing problem" do
    post do_import_problems_path, params: {
      problem: { name: @problem.name, full_name: "Updated by admin",
                 file: fixture_zip, groups: "",
                 input_pattern: "*.in", sol_pattern: "*.sol",
                 time_limit: 1, memory_limit: 64 }
    }
    assert_equal "Updated by admin", @problem.reload.full_name
  end
```

- [ ] **Step 2: Run — expect FAIL** (mary's import silently updates `pct_fibo`)

- [ ] **Step 3: Implement** — in `do_import`, after the existing group check
(`unless @current_user.admin? || ...editor` block) and before
`pi = ProblemImporter.new`, insert:

```ruby
    # importing over an existing name updates that problem — require edit rights on it
    existing = Problem.find_by(name: name)
    if existing && !@current_user.admin? &&
       !@current_user.problems_for_action(:edit).where(id: existing.id).exists?
      @errors = ["A problem named '#{name}' already exists and you do not have the right to edit it"]
      render :import and return
    end
```

- [ ] **Step 4: Run — expect PASS (whole controller file)**

- [ ] **Step 5: Commit with changelog** → `### Security`:

```markdown
- **Importing a problem under an existing name now requires edit rights on
  that problem** — previously any group editor could silently overwrite any
  problem in the system by importing a zip with the same short name. Admin
  re-import-to-update behavior is unchanged.
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/controllers/problems_controller.rb test/controllers/problems_controller_test.rb CHANGELOG.md -m "security: require edit rights to import over an existing problem name

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: `download_archive` without a live dataset — friendly error

**Files:**
- Modify: `app/controllers/problems_controller.rb` (`download_archive`)
- Test: `test/controllers/problems_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  test "download_archive on a problem without live dataset redirects with alert" do
    bare = Problem.create!(name: "no_live_ds", full_name: "Bare")
    get download_archive_problem_path(bare)
    assert_redirected_to problems_path
    assert_match(/no live dataset/i, flash[:alert])
  end
```

- [ ] **Step 2: Run — expect FAIL** (500 from `raise 'No live dataset'`)

- [ ] **Step 3: Implement**

```ruby
  def download_archive
    unless @problem.live_dataset
      redirect_to problems_path, alert: "Problem '#{@problem.name}' has no live dataset to export."
      return
    end
    result = @problem.export
    send_file result[:zip], type: 'application/x-zip',  disposition: 'attachment', filename: result[:zip].basename.to_s
  end
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit with changelog** → `### Fixed`:

```markdown
- **Downloading the archive of a problem with no live dataset** shows an
  alert instead of a 500 error page.
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/controllers/problems_controller.rb test/controllers/problems_controller_test.rb CHANGELOG.md -m "fix: friendly error for download_archive without live dataset

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Scorer wording (keep `.min`) + delete dead import code

**Files:**
- Modify: `app/engine/scorer.rb` (`group_min` — rename + comments only, NO behavior change)
- Modify: `doc/dataset-scoring-and-evaluation.md:17,20`
- Modify: `app/models/problem.rb` (delete `create_from_import_form_params`)

Decision record (spec §Package 1 item 19, decided by dae): group weight
semantics stay **min**; docs said "max" and were wrong.

- [ ] **Step 1: Rename the misleading variable in `scorer.rb#group_min`** —
`max_weight` → `group_weight` everywhere inside the method (4 occurrences),
and update the method comment:

```ruby
  # score_type :group_min — IOI/ICPC subtask style. For each group take
  # the minimum testcase score, multiply by the group's weight, then
  # normalize to 100. One failure in a group drags the whole group to
  # its min. A group has ONE weight by convention (CMS semantics); if
  # weights inside a group differ, the minimum weight is used — the
  # importer warns about such packages.
```

The tally lines become:

```ruby
        sum_user_score += min_score * group_weight
        sum_total_weight += group_weight
```
```ruby
        min_score = score
        group_weight = weight
      else
        min_score = [min_score, score].min
        group_weight = [group_weight, weight].min
```

(and the initialization `max_weight = 0` → `group_weight = 0`).

- [ ] **Step 2: Fix the doc table** — `doc/dataset-scoring-and-evaluation.md`
line 17, replace the `group_min` row with:

```markdown
| `group_min` | Per group, take the *minimum* score in that group × the group's weight (the *minimum* weight found in the group — by convention all testcases in a group share one weight); then `Σ / total weight × 100`. | **IOI/ICPC subtask style.** A group only earns points if *every* testcase in it passes — one failure drags the whole group to its minimum. The importer warns when a package declares mixed weights inside a group. |
```

- [ ] **Step 3: Delete dead code** — remove
`Problem.create_from_import_form_params` (`app/models/problem.rb:253-283`,
the whole method incl. the `import_to_db`/`TestdataImporter` body). Verify
first:

```bash
grep -rn "create_from_import_form_params\|extract_params_and_check" app lib config test spec
```
Expected: only the method's own lines in `app/models/problem.rb` (note:
`extract_params_and_check` has NO definition anywhere — the method was
already un-runnable).

- [ ] **Step 4: Run the affected suites**

Run: `bin/rails test test/models/ test/engine/`
Expected: `0 failures, 0 errors` (rename is behavior-neutral).

- [ ] **Step 5: Commit** (no changelog — internal comment/doc/dead-code only)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit app/engine/scorer.rb doc/dataset-scoring-and-evaluation.md app/models/problem.rb -m "docs: group_min uses min weight per group (rename var, fix docs); drop dead import method

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Full sweep + backlog entries

**Files:**
- Modify: `doc/backlog.md`

- [ ] **Step 1: Run the full minitest suite**

Run: `bin/rails test`
Expected: `0 failures, 0 errors` (system tests are separate; don't run them).
If anything fails, fix before proceeding — do not skip tests.

- [ ] **Step 2: Rubocop the touched files**

```bash
bundle exec rubocop app/engine/problem_importer.rb app/engine/problem_exporter.rb app/engine/option_const.rb app/engine/scorer.rb app/controllers/problems_controller.rb test/engine test/controllers/problems_controller_test.rb
```
Expected: no offenses (fix any that appear).

- [ ] **Step 3: Add backlog entries** — append to `doc/backlog.md` under an
appropriate section (create `## Import/Export & CMS interop` if none fits):

```markdown
## Import/Export & CMS interop (from doc/problem-import-export-design-2026-07-14.md)

- Communication task support in the judge (manager process + FIFOs) — unblocks CMS Communication import/export.
- OutputOnly grading support — unblocks CMS OutputOnly import/export.
- GroupMinPrereq scoring in cafe's scorer (`score_param` to hold the prereq DAG) — unblocks importing dae's CMS camp tasks that use the custom score type.
- File-I/O task support (or a permanent-rejection decision) for Italian-format tasks with `infile`/`outfile`.
- Checker protocol adapter so `custom_cafe` checkers can be exported to CMS.
- C++ relative comparator (CMS-side equivalent of `lib/checker/relative.rb`).
- Group-weight uniformity validation in the dataset edit UI (import already warns).
- Approach-C IR refactor of import/export — only if supported formats multiply beyond Italian+TPS.
```

- [ ] **Step 4: Production data-hygiene scan (informational, at next deploy)**

Note for the operator (dae) — run against production once, expected `{}`:

```ruby
Testcase.joins(:dataset).where(datasets: {score_type: 1})
        .group(:dataset_id, :group).having("COUNT(DISTINCT weight) > 1").count
```

- [ ] **Step 5: Commit** (no changelog — backlog/dev docs)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg commit doc/backlog.md -m "doc: backlog entries for CMS-interop capability gaps

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
