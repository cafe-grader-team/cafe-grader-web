# CMS → cafe Task Clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `rake "cms:clone[mar2025_eatingfish]"` clones a Batch task (all datasets) from the c2.thailandoi.org CMS into the local cafe-grader DB, via a server-side extractor that wraps the official `cmsDumpExporter` and a cafe-side bundle→staging converter feeding the untouched trusted `ProblemImporter`.

**Architecture:** Two isolated units with a dumb bundle between them. Unit 1 (`script/cms_extract/extract_task.py`, streamed over ssh, runs as `cms`) invokes the official `cmsDumpExporter -F -S -U -P` for ALL serialization, filters the one task's subtree (users/password-hashes never leave the server), fetches only that task's blobs via CMS `FileCacher`, and streams a tar to stdout. Unit 2 (`Converters::CmsDumpConverter`, pure dir→dir) maps the bundle to the canonical cafe staging layout (multi-dataset: active→root/live, siblings→`datasets/<name>/`), enforcing the reject/skip matrix; then `ProblemImporter#import_dataset_from_dir` (existing, unmodified) writes the DB. Spec: `docs/superpowers/specs/2026-08-02-cms-clone-import-design.md`.

**Tech Stack:** Ruby 3.4.4 / Rails 8.0 (zeitwerk: `app/engine/converters/x.rb` ⇒ `Converters::X`), minitest, Python 3.6 (server side — no f-strings needed, stdlib + `cms` package from `/home/cms/cms_venv`), Mercurial.

## Global Constraints

- **VCS is Mercurial; all commits land on the `master` bookmark.** Before EVERY commit run the *conditional gate* (a bare `hg log && hg commit` chain gates nothing):
  ```bash
  [ "$(hg log -r . --template '{activebookmark}')" = "master" ] && hg commit <files> -m "..." || echo "NOT ON master — STOP"
  ```
  If the working copy is parked on `chula_cp` (it may be — dae runs the dev server there), do NOT `hg update` it. Instead use the throwaway-clone route: `hg clone -u master /home/dae/cafe-grader/web <scratch>/clone`, apply the task's files there, commit, `hg push -B master /home/dae/cafe-grader/web`, remove the clone.
- **Name explicit files in every `hg commit`** (the repo often has unrelated dirty files). End commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Run tests with `bin/rails test <path>`. Do NOT run `bin/rails check` per task; the full sweep happens once in Task 5.
- **`ProblemImporter` / `ProblemExporter` / `OptionConst` are NOT modified** by this project. The converter must emit what the importer already reads.
- **Nothing in this project writes to the CMS server.** The extractor is read-only (official exporter + `FileCacher` reads); its work dir is `0700` under `/tmp` and removed in the same run.
- **No server names or credentials in committed files** except the `.sample` config (dae approved naming the host in the sample).
- CHANGELOG.md: exactly one operator-facing bullet, added in Task 5's commit (earlier tasks are internal — no changelog).
- CMS dump facts (verified on c2, 2026-08-02): dump `_version` = **39** (CMS 1.4.dev3); `Dataset.task_type_parameters` for Batch = `[compilation, [infile, outfile], output_eval]` e.g. `["grader", ["", ""], "diff"]`; GroupMin integer params consume testcases in **lexicographic codename order** (`sorted()` in `ScoreTypeGroup`, "XXX Lexicographical order by codename"); regex params use Python `re.match` (start-anchored) semantics.

## File Structure

- `test/cms_bundles/eatingfish_mini/` — **create** (Task 1): committed fixture bundle (`task.json` + `files/<digest>`), miniature of the real `mar2025_eatingfish` dump subtree
- `test/engine/converters/cms_bundle_fixture_test.rb` — **create** (Task 1): fixture-integrity guard
- `app/engine/converters/cms_dump_converter.rb` — **create** (Task 2): `Converters::CmsDumpConverter`
- `test/engine/converters/cms_dump_converter_test.rb` — **create** (Task 2): converter unit tests
- `test/engine/converters/cms_clone_integration_test.rb` — **create** (Task 3): converter → real `ProblemImporter` → DB assertions
- `script/cms_extract/extract_task.py` — **create** (Task 4): server-side extractor
- `test/engine/converters/extract_task_filter_test.rb` — **create** (Task 4): shells `python3` to test the pure filter function
- `lib/tasks/cms.rake` — **create** (Task 5): `cms:clone[name]`
- `config/cms_remote.yml.sample` — **create** (Task 5); `.gitignore` — **modify** (Task 5): ignore `config/cms_remote.yml`
- `CHANGELOG.md` — **modify** (Task 5)

---

### Task 1: Fixture bundle `eatingfish_mini`

A committed miniature CMS bundle, shaped exactly like the real dump subtree (verified against the live `mar2025_eatingfish` dump). Later tasks' tests all consume it; a fixture-integrity test guards it.

**Files:**
- Create: `test/cms_bundles/eatingfish_mini/task.json`
- Create: `test/cms_bundles/eatingfish_mini/files/*` (11 tiny blobs)
- Test: `test/engine/converters/cms_bundle_fixture_test.rb`

**Interfaces:**
- Produces: the fixture bundle dir consumed by Tasks 2–4's tests. `task.json` schema: `{bundle_version: 1, dump_version: 39, task_id: "408", objects: {<id>: <official dump object>}}`.

- [ ] **Step 1: Create the bundle directory and `task.json`**

`test/cms_bundles/eatingfish_mini/task.json`:

```json
{
 "bundle_version": 1,
 "dump_version": 39,
 "task_id": "408",
 "objects": {
  "408": {
   "_class": "Task",
   "name": "eatingfish_mini",
   "title": "กินปลา mini",
   "num": 1,
   "contest": "7",
   "submission_format": ["eatingfish.%l"],
   "primary_statements": ["th"],
   "statements": {"en": "1415", "th": "1416"},
   "attachments": {"starter.zip": "1417"},
   "datasets": ["1418", "1414"],
   "active_dataset": "1414",
   "score_mode": "max_subtask",
   "score_precision": 0,
   "token_mode": "disabled",
   "max_submission_number": 75
  },
  "1414": {
   "_class": "Dataset", "task": "408", "description": "main",
   "autojudge": false, "time_limit": 1.0, "memory_limit": 512,
   "task_type": "Batch",
   "task_type_parameters": ["grader", ["", ""], "diff"],
   "score_type": "GroupMin",
   "score_type_parameters": [[30, 1], [70, 2]],
   "managers": {"eatingfish.h": "10096", "grader.cpp": "10095"},
   "testcases": {"1-01": "20001", "2-01": "20002", "2-02": "20003"}
  },
  "1418": {
   "_class": "Dataset", "task": "408", "description": "rev2",
   "autojudge": false, "time_limit": 2.0, "memory_limit": 256,
   "task_type": "Batch",
   "task_type_parameters": ["alone", ["", ""], "diff"],
   "score_type": "Sum",
   "score_type_parameters": 100,
   "managers": {},
   "testcases": {"1-01": "20004"}
  },
  "10095": {"_class": "Manager", "dataset": "1414", "filename": "grader.cpp", "digest": "dig-grader"},
  "10096": {"_class": "Manager", "dataset": "1414", "filename": "eatingfish.h", "digest": "dig-header"},
  "1415": {"_class": "Statement", "task": "408", "language": "en", "digest": "dig-st-en"},
  "1416": {"_class": "Statement", "task": "408", "language": "th", "digest": "dig-st-th"},
  "1417": {"_class": "Attachment", "task": "408", "filename": "starter.zip", "digest": "dig-att"},
  "20001": {"_class": "Testcase", "dataset": "1414", "codename": "1-01", "public": true,  "input": "dig-in-101", "output": "dig-out-101"},
  "20002": {"_class": "Testcase", "dataset": "1414", "codename": "2-01", "public": false, "input": "dig-in-201", "output": "dig-out-201"},
  "20003": {"_class": "Testcase", "dataset": "1414", "codename": "2-02", "public": false, "input": "dig-in-202", "output": "dig-out-202"},
  "20004": {"_class": "Testcase", "dataset": "1418", "codename": "1-01", "public": true,  "input": "dig-in-101", "output": "dig-out-101"}
 }
}
```

(Real dump objects carry more keys — `feedback_level`, token fields, etc. The converter ignores unknown keys; the fixture keeps the consumed subset plus a few representative extras. Digests are opaque filenames to the converter, so readable fake ids are fine.)

- [ ] **Step 2: Create the 11 blob files**

```bash
cd test/cms_bundles/eatingfish_mini && mkdir files
printf '#include <cstdio>\n#include "eatingfish.h"\nint main(){int a,b;scanf("%%d %%d",&a,&b);printf("%%d\\n",solve(a,b));}\n' > files/dig-grader
printf '#ifndef EATINGFISH_H\n#define EATINGFISH_H\nint solve(int a, int b);\n#endif\n' > files/dig-header
printf '%%PDF-1.4 fake thai statement\n' > files/dig-st-th
printf '%%PDF-1.4 fake english statement\n' > files/dig-st-en
printf 'fake zip bytes\n' > files/dig-att
printf '1 2\n' > files/dig-in-101;  printf '3\n'  > files/dig-out-101
printf '5 7\n' > files/dig-in-201;  printf '12\n' > files/dig-out-201
printf '2 2\n' > files/dig-in-202;  printf '4\n'  > files/dig-out-202
```

- [ ] **Step 3: Write the fixture-integrity test**

`test/engine/converters/cms_bundle_fixture_test.rb`:

```ruby
require 'test_helper'

# Guards the committed CMS bundle fixture that the converter tests build on:
# valid JSON, expected versions, and no dangling digest references.
class CmsBundleFixtureTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/cms_bundles/eatingfish_mini')

  test 'fixture task.json parses with expected versions and complete blobs' do
    data = JSON.parse(File.read(FIXTURE.join('task.json')))
    assert_equal 1, data['bundle_version']
    assert_equal 39, data['dump_version']
    objects = data['objects']
    task = objects[data['task_id']]
    assert_equal 'Task', task['_class']

    digests = []
    task['statements'].each_value  { |id| digests << objects[id]['digest'] }
    task['attachments'].each_value { |id| digests << objects[id]['digest'] }
    task['datasets'].each do |did|
      ds = objects[did]
      ds['managers'].each_value { |id| digests << objects[id]['digest'] }
      ds['testcases'].each_value do |id|
        digests << objects[id]['input'] << objects[id]['output']
      end
    end
    digests.uniq.each do |dig|
      assert FIXTURE.join('files', dig).exist?, "missing blob files/#{dig}"
    end
  end
end
```

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/engine/converters/cms_bundle_fixture_test.rb`
Expected: 1 run, 0 failures.

- [ ] **Step 5: Commit**

```bash
[ "$(hg log -r . --template '{activebookmark}')" = "master" ] && \
hg add test/cms_bundles/eatingfish_mini test/engine/converters/cms_bundle_fixture_test.rb && \
hg commit test/cms_bundles/eatingfish_mini test/engine/converters/cms_bundle_fixture_test.rb \
  -m "test: CMS bundle fixture eatingfish_mini (dump-subtree miniature)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" || echo "NOT ON master — use the clone route (Global Constraints)"
```

---

### Task 2: `Converters::CmsDumpConverter`

The complete converter, driven by unit tests against the Task 1 fixture (with in-test JSON mutations for every reject/skip path).

**Files:**
- Create: `app/engine/converters/cms_dump_converter.rb`
- Test: `test/engine/converters/cms_dump_converter_test.rb`

**Interfaces:**
- Consumes: bundle dir layout from Task 1 (`task.json` + `files/<digest>`); `OptionConst` / `ProblemImporter::RESERVED_DATASETS_DIRNAME` constants (existing, read-only).
- Produces: `Converters::CmsDumpConverter#convert(bundle_dir, staging_dir) → {log: [String], warnings: [String], errors: [String]}`; `#problem_meta → {name:, full_name:, live_dataset_name:}` (populated when errors empty). Tasks 3 and 5 call exactly these.

- [ ] **Step 1: Write the failing tests**

`test/engine/converters/cms_dump_converter_test.rb`:

```ruby
require 'test_helper'

class CmsDumpConverterTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/cms_bundles/eatingfish_mini')

  setup    { @tmp = Pathname.new(Dir.mktmpdir('cms_conv_test_')) }
  teardown { FileUtils.rm_rf(@tmp) }

  # Copy the fixture, optionally mutate its task.json, return the bundle dir.
  def bundle(mutate: nil)
    dir = @tmp + 'bundle'
    FileUtils.cp_r(FIXTURE, dir)
    if mutate
      path = dir + 'task.json'
      data = JSON.parse(File.read(path))
      mutate.call(data)
      File.write(path, JSON.generate(data))
    end
    dir
  end

  def convert(mutate: nil)
    @conv = Converters::CmsDumpConverter.new
    @staging = @tmp + 'staging'
    @result = @conv.convert(bundle(mutate: mutate), @staging)
  end

  def staging_cfg
    YAML.safe_load(File.read(@staging + 'config.yml'), symbolize_names: true)
  end

  test 'rejects wrong bundle_version' do
    convert(mutate: ->(d) { d['bundle_version'] = 2 })
    assert_match(/bundle_version/, @result[:errors].join)
  end

  test 'rejects wrong dump_version' do
    convert(mutate: ->(d) { d['dump_version'] = 40 })
    assert_match(/dump _version/, @result[:errors].join)
  end

  test 'clean fixture converts without errors and exposes problem_meta' do
    convert
    assert_equal [], @result[:errors]
    assert_equal({ name: 'eatingfish_mini', full_name: 'กินปลา mini',
                   live_dataset_name: 'main' }, @conv.problem_meta)
  end

  test 'root config carries problem and active dataset fields' do
    convert
    cfg = staging_cfg
    assert_equal 'eatingfish_mini', cfg[:name]
    assert_equal 'batch', cfg[:task_type]
    assert_equal 'with_managers', cfg[:compilation_type]
    assert_equal 'eatingfish.cpp', cfg[:submission_filename]
    assert_equal 'cpp', cfg[:permitted_lang]
    assert_equal 1.0, cfg[:time_limit]
    assert_equal 512, cfg[:memory_limit]
    assert_equal 'group_min', cfg[:score_type]
    assert_equal 'default', cfg[:evaluation_type]
    assert_equal 'grader.cpp', cfg[:main_filename]
    assert_equal ['grader.cpp'], cfg[:main]
  end

  test 'GroupMin integer params slice lexicographically sorted codenames' do
    convert
    tcs = staging_cfg[:testcases]
    assert_equal({ group: 1, group_name: '1', weight: 30 }, tcs[:'1-01'])
    assert_equal({ group: 2, group_name: '2', weight: 70 }, tcs[:'2-01'])
    assert_equal({ group: 2, group_name: '2', weight: 70 }, tcs[:'2-02'])
  end

  test 'testcase blobs land as codename.in/.sol' do
    convert
    assert_equal "1 2\n", File.read(@staging + 'testcases' + '1-01.in')
    assert_equal "3\n",   File.read(@staging + 'testcases' + '1-01.sol')
  end

  test 'managers copied; statement picks primary th; attachment direct' do
    convert
    assert File.exist?(@staging + 'managers' + 'grader.cpp')
    assert File.exist?(@staging + 'managers' + 'eatingfish.h')
    assert_equal File.read(FIXTURE + 'files' + 'dig-st-th'),
                 File.read(@staging + 'statement.pdf')
    assert File.exist?(@staging + 'attachment' + 'starter.zip')
    assert_match(/language 'th'/, @result[:log].join("\n"))
    assert_match(/statement language 'en' skipped/, @result[:warnings].join("\n"))
  end

  test 'non-active dataset becomes datasets/<name> fragment without problem keys' do
    convert
    assert_equal ['rev2'], staging_cfg[:additional_datasets]
    frag = YAML.safe_load(File.read(@staging + 'datasets' + 'rev2' + 'config.yml'),
                          symbolize_names: true)
    assert_equal 'rev2', frag[:ds_name]
    assert_equal 2.0, frag[:time_limit]
    assert_equal 256, frag[:memory_limit]
    assert_equal 'sum', frag[:score_type]
    assert_equal({ group: 1, group_name: '1', weight: 1 }, frag[:testcases][:'1-01'])
    assert File.exist?(@staging + 'datasets' + 'rev2' + 'testcases' + '1-01.in')
    refute frag.key?(:name)
    refute frag.key?(:compilation_type)
    refute frag.key?(:submission_filename)
  end

  test 'active dataset violation rejects the whole task' do
    convert(mutate: ->(d) { d['objects']['1414']['task_type'] = 'Communication' })
    assert_match(/active dataset .*task_type 'Communication'/, @result[:errors].join)
  end

  test 'file-IO active dataset rejects' do
    convert(mutate: ->(d) {
      d['objects']['1414']['task_type_parameters'] = ['grader', ['in.txt', 'out.txt'], 'diff']
    })
    assert_match(%r{file-I/O}, @result[:errors].join)
  end

  test 'GroupMinPrereq active dataset rejects' do
    convert(mutate: ->(d) { d['objects']['1414']['score_type'] = 'GroupMinPrereq' })
    assert_match(/score_type 'GroupMinPrereq'/, @result[:errors].join)
  end

  test 'non-active dataset violation only skips that dataset' do
    convert(mutate: ->(d) { d['objects']['1418']['task_type'] = 'OutputOnly' })
    assert_equal [], @result[:errors]
    assert_match(/skipped non-active dataset 'rev2'/, @result[:warnings].join)
    refute File.exist?((@staging + 'datasets').to_s)
    refute staging_cfg.key?(:additional_datasets)
  end

  test 'GroupMin count mismatch rejects' do
    convert(mutate: ->(d) { d['objects']['1414']['score_type_parameters'] = [[30, 1], [70, 5]] })
    assert_match(/counts sum to 6 but dataset has 3/, @result[:errors].join)
  end

  test 'GroupMin regex params assign by anchored match' do
    convert(mutate: ->(d) { d['objects']['1414']['score_type_parameters'] = [[40, '1-.*'], [60, '2-.*']] })
    assert_equal [], @result[:errors]
    tcs = staging_cfg[:testcases]
    assert_equal({ group: 1, group_name: '1', weight: 40 }, tcs[:'1-01'])
    assert_equal({ group: 2, group_name: '2', weight: 60 }, tcs[:'2-01'])
    assert_equal({ group: 2, group_name: '2', weight: 60 }, tcs[:'2-02'])
  end

  test 'GroupMin regex leaving testcases uncovered rejects' do
    convert(mutate: ->(d) { d['objects']['1414']['score_type_parameters'] = [[40, '1-.*']] })
    assert_match(/match no GroupMin pattern: 2-01, 2-02/, @result[:errors].join)
  end

  test 'comparator eval maps to custom_cms and pulls the checker manager' do
    convert(mutate: lambda { |d|
      d['objects']['1414']['task_type_parameters'] = ['grader', ['', ''], 'comparator']
      d['objects']['1414']['managers'] = d['objects']['1414']['managers'].merge('checker' => '10097')
      d['objects']['10097'] = { '_class' => 'Manager', 'dataset' => '1414',
                                'filename' => 'checker', 'digest' => 'dig-header' }
    })
    assert_equal [], @result[:errors]
    assert_equal 'custom_cms', staging_cfg[:evaluation_type]
    assert File.exist?(@staging + 'checker' + 'checker')
    refute File.exist?(@staging + 'managers' + 'checker')
    assert_match(/prebuilt/, @result[:warnings].join)
  end

  test 'pdf attachment is wrapped in a zip to avoid root glob collision' do
    convert(mutate: lambda { |d|
      d['objects']['408']['attachments'] = { 'notes.pdf' => '1417' }
      d['objects']['1417']['filename'] = 'notes.pdf'
    })
    assert_equal [], @result[:errors]
    refute File.exist?(@staging + 'attachment' + 'notes.pdf')
    assert File.exist?(@staging + 'attachment' + 'eatingfish_mini-files.zip')
  end

  test 'missing blob rejects' do
    convert(mutate: ->(d) { d['objects']['20001']['input'] = 'dig-nonexistent' })
    assert_match(/blob missing: dig-nonexistent/, @result[:errors].join)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/engine/converters/cms_dump_converter_test.rb`
Expected: FAIL/ERROR — `NameError: uninitialized constant Converters`.

- [ ] **Step 3: Write the converter**

`app/engine/converters/cms_dump_converter.rb`:

```ruby
require 'json'
require 'open3'
require 'fileutils'

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
  EVAL_MAP       = { 'diff' => 'default', 'comparator' => 'custom_cms' }.freeze

  # Attachment filenames that would collide with ProblemImporter's root-level
  # recursive globs (*.pdf statement, *.md description, *.in/*.sol testcases)
  # get wrapped in a zip instead of shipped bare.
  RISKY_ATTACHMENT = /\.(pdf|md|in|sol|yml)\z/i

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
    @active = @objects[active_id]
    reject!('task has no active dataset') unless @active
    reasons = dataset_reject_reasons(@active)
    if reasons.any?
      reject!("active dataset '#{ds_display_name(@active)}': #{reasons.join('; ')}")
    end
    @others = []
    (@task['datasets'] || []).map(&:to_s).reject { |i| i == active_id }.each do |id|
      ds = @objects[id]
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
      _plan, plan_errors = build_group_plan(ds)
      reasons.concat(plan_errors)
    end
    reasons
  end

  # => [ {codename => {group:, group_name:, weight:}}, [error strings] ]
  # Deterministic; called once for validation and once for writing.
  def build_group_plan(ds)
    codenames = (ds['testcases'] || {}).keys
    bad = codenames.reject { |c| c.match?(/\A[\w.\-]+\z/) }
    return [{}, ["unsafe testcase codenames: #{bad.join(', ')}"]] if bad.any?

    # CMS ScoreTypeGroup consumes testcases in lexicographic codename order.
    sorted = codenames.sort
    case ds['score_type']
    when 'Sum'
      [sorted.to_h { |c| [c, { group: 1, group_name: '1', weight: 1 }] }, []]
    when 'GroupMin'
      params = ds['score_type_parameters']
      unless params.is_a?(Array) && params.all? { |p| p.is_a?(Array) && p.size == 2 }
        return [{}, ["GroupMin parameters malformed: #{params.inspect}"]]
      end
      if params.all? { |_m, t| t.is_a?(Integer) }
        total = params.sum { |_m, t| t }
        unless total == sorted.size
          return [{}, ["GroupMin testcase counts sum to #{total} but dataset has #{sorted.size} testcases"]]
        end
        plan = {}
        cursor = 0
        params.each_with_index do |(points, count), i|
          sorted[cursor, count].each do |c|
            plan[c] = { group: i + 1, group_name: (i + 1).to_s, weight: points }
          end
          cursor += count
        end
        [plan, []]
      elsif params.all? { |_m, t| t.is_a?(String) }
        plan = {}
        errs = []
        params.each_with_index do |(points, pattern), i|
          re = /\A(?:#{pattern})/ # CMS uses re.match => start-anchored
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
        [errs.any? ? {} : plan, errs]
      else
        [{}, ['GroupMin parameters mix integer and regex styles (unsupported)']]
      end
    else
      [{}, []] # unreachable: score_type gated in dataset_reject_reasons
    end
  end

  def write_staging
    @staging.mkpath
    cfg = problem_level_config
    write_dataset_into(@active, @staging, cfg)
    write_statement
    write_attachments
    additional = []
    @others.each do |ds|
      dirname = unique_dirname(additional, ds_display_name(ds))
      dir = @staging + ProblemImporter::RESERVED_DATASETS_DIRNAME + dirname
      frag = { ds_name: ds_display_name(ds) }
      write_dataset_into(ds, dir, frag)
      write_yaml(dir + OptionConst::YAML_FILENAME, frag)
      additional << dirname
      @log << "additional dataset '#{ds_display_name(ds)}' -> " \
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

    managers = ds['managers'] || {}
    if (checker_id = managers['checker'])
      copy_blob(@objects[checker_id]['digest'], dir + 'checker' + 'checker')
      @warnings << "dataset '#{ds_display_name(ds)}': CMS comparator copied as checker/checker — " \
                   'CMS checkers are prebuilt binaries; verify it runs on the cafe judge host ' \
                   '(or replace with recompiled source)'
    end
    manager_names = managers.keys - ['checker']
    manager_names.each do |name|
      copy_blob(@objects[managers[name]]['digest'], dir + 'managers' + name)
    end
    if compilation == 'grader'
      main = manager_names.include?('grader.cpp') ? 'grader.cpp' : manager_names.sort.find { |n| n.end_with?('.cpp') }
      cfg[:main] = [main]
      cfg[:main_filename] = main
    end

    plan, _errs = build_group_plan(ds)
    if ds['score_type'] == 'Sum'
      @log << "dataset '#{ds_display_name(ds)}': CMS Sum " \
              "(params #{ds['score_type_parameters'].inspect}) -> cafe sum, every testcase weight 1"
    end
    tc_cfg = {}
    (ds['testcases'] || {}).sort.each do |codename, tc_id|
      tc = @objects[tc_id.to_s]
      copy_blob(tc['input'],  dir + 'testcases' + "#{codename}.in")
      copy_blob(tc['output'], dir + 'testcases' + "#{codename}.sol")
      tc_cfg[codename] = plan[codename]
    end
    cfg[:testcases] = tc_cfg
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
    copy_blob(@objects[statements[lang]]['digest'], @staging + OptionConst::DEFAULT[:file][:statement])
    @log << "statement: language '#{lang}' -> #{OptionConst::DEFAULT[:file][:statement]}"
    (statements.keys - [lang]).sort.each do |l|
      @warnings << "statement language '#{l}' skipped (cafe holds one statement)"
    end
  end

  def write_attachments
    atts = (@task['attachments'] || {}).map { |name, id| [name, @objects[id.to_s]['digest']] }
    return if atts.empty?

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

  def write_yaml(path, hash)
    path.dirname.mkpath
    File.write(path, hash.deep_stringify_keys.to_yaml)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/engine/converters/cms_dump_converter_test.rb`
Expected: 17 runs, 0 failures. Also re-run Task 1's fixture test (same dir):
`bin/rails test test/engine/converters/` — all green.

- [ ] **Step 5: Commit**

```bash
[ "$(hg log -r . --template '{activebookmark}')" = "master" ] && \
hg add app/engine/converters/cms_dump_converter.rb test/engine/converters/cms_dump_converter_test.rb && \
hg commit app/engine/converters/cms_dump_converter.rb test/engine/converters/cms_dump_converter_test.rb \
  -m "feat(cms-clone): CMS dump-bundle -> cafe staging converter (multi-dataset, GroupMin int+regex, reject/skip matrix)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" || echo "NOT ON master — use the clone route (Global Constraints)"
```

---

### Task 3: Integration through the real `ProblemImporter`

Prove the staging dir the converter emits is exactly what the trusted importer expects — both datasets, fields, blobs, attachments — writing to the test DB.

**Files:**
- Test: `test/engine/converters/cms_clone_integration_test.rb`

**Interfaces:**
- Consumes: `Converters::CmsDumpConverter#convert` / `#problem_meta` (Task 2); `ProblemImporter#import_dataset_from_dir(dir, name, full_name:)` (existing).
- Produces: nothing new — this is the behavioral gate for Tasks 1+2.

- [ ] **Step 1: Write the failing-or-passing integration test** (it should pass immediately if Task 2 is correct; a failure here is a real mapping bug)

`test/engine/converters/cms_clone_integration_test.rb`:

```ruby
require 'test_helper'

# End-to-end (offline half): fixture bundle -> CmsDumpConverter -> real
# ProblemImporter -> DB. The live-server half is the operator gate (Task 6).
class CmsCloneIntegrationTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/cms_bundles/eatingfish_mini')

  test 'converted bundle imports with both datasets, fields, and blobs intact' do
    Dir.mktmpdir('cms_clone_int_') do |tmp|
      staging = File.join(tmp, 'staging')
      conv = Converters::CmsDumpConverter.new
      res = conv.convert(FIXTURE, staging)
      assert_equal [], res[:errors]

      pi = ProblemImporter.new
      log = pi.import_dataset_from_dir(staging, conv.problem_meta[:name],
                                       full_name: conv.problem_meta[:full_name])
      assert_kind_of Array, log
      assert_empty pi.errors

      problem = Problem.find_by(name: 'eatingfish_mini')
      assert problem, 'problem not created'
      assert_equal 'กินปลา mini', problem.full_name
      assert problem.with_managers?
      assert_equal 'eatingfish.cpp', problem.submission_filename
      assert_equal false, problem.available, 'clone must land unavailable'
      assert problem.statement.attached?
      assert problem.attachment.attached?
      assert_equal 'starter.zip', problem.attachment.filename.to_s

      live = problem.live_dataset
      assert_equal 1.0, live.time_limit
      assert_equal 512, live.memory_limit
      assert live.st_group_min?
      assert_equal 'grader.cpp', live.main_filename
      assert_equal %w[eatingfish.h grader.cpp],
                   live.managers.map { |m| m.filename.to_s }.sort
      tcs = live.testcases.order(:num)
      assert_equal %w[1-01 2-01 2-02], tcs.map(&:code_name)
      assert_equal [30, 70, 70], tcs.map(&:weight)
      assert_equal [1, 2, 2], tcs.map(&:group)
      assert_equal "1 2\n", tcs.first.inp_file.download
      assert_equal "3\n", tcs.first.ans_file.download

      rev2 = problem.datasets.find_by(name: 'rev2')
      assert rev2, 'additional dataset not imported'
      refute_equal problem.live_dataset_id, rev2.id
      assert rev2.st_sum?
      assert_equal 2.0, rev2.time_limit
      assert_equal 256, rev2.memory_limit
      assert_equal ['1-01'], rev2.testcases.map(&:code_name)
      assert_equal [1], rev2.testcases.map(&:weight)
    end
  end
end
```

- [ ] **Step 2: Run it**

Run: `bin/rails test test/engine/converters/cms_clone_integration_test.rb`
Expected: PASS. If it fails, the converter (not the importer) is wrong — fix Task 2's file, keeping its unit tests green.

- [ ] **Step 3: Commit**

```bash
[ "$(hg log -r . --template '{activebookmark}')" = "master" ] && \
hg add test/engine/converters/cms_clone_integration_test.rb && \
hg commit test/engine/converters/cms_clone_integration_test.rb \
  -m "test(cms-clone): bundle -> converter -> ProblemImporter integration (both datasets round into the DB)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" || echo "NOT ON master — use the clone route (Global Constraints)"
```

---

### Task 4: Server-side extractor `extract_task.py`

Python 3.6-compatible, streamed to the server per run (never installed). Wraps the official exporter; adds the subtree filter + digest fetch. The pure filter function gets a real committed test (shelling the dev box's `python3`); the CMS-coupled parts are exercised by the Task 6 operator gate.

**Files:**
- Create: `script/cms_extract/extract_task.py`
- Test: `test/engine/converters/extract_task_filter_test.rb`

**Interfaces:**
- Consumes: nothing from other tasks (server side).
- Produces: bundle tar on stdout — `bundle/task.json` + `bundle/files/<digest>` in the exact schema of Task 1's fixture. Invocation contract (Task 5 builds this): `ssh HOST sudo -n -u cms <venv-python> - TASKNAME < extract_task.py > bundle.tar`, exit 0 on success, logs on stderr. Module-level function `build_subtree(objects, task_name) -> (task_id, subtree, digests)` (pure, testable).

- [ ] **Step 1: Write the failing filter test**

`test/engine/converters/extract_task_filter_test.rb`:

```ruby
require 'test_helper'
require 'open3'

# extract_task.py runs on the CMS server, but its subtree filter is a pure
# function — tested here by shelling the dev box's python3 against the
# committed fixture's object map plus an injected User row (which must be
# excluded: password hashes never enter a bundle).
class ExtractTaskFilterTest < ActiveSupport::TestCase
  SCRIPT  = Rails.root.join('script/cms_extract/extract_task.py')
  FIXTURE = Rails.root.join('test/cms_bundles/eatingfish_mini/task.json')

  PYTEST = <<~PY
    import importlib.util, json, sys
    spec = importlib.util.spec_from_file_location("extract_task", sys.argv[1])
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    data = json.load(open(sys.argv[2]))
    objs = dict(data["objects"])
    objs["999"] = {"_class": "User", "username": "x", "password": "hash"}
    objs["998"] = {"_class": "Participation", "user": "999", "contest": "7"}
    tid, subtree, digests = m.build_subtree(objs, "eatingfish_mini")
    assert tid == "408", tid
    assert "999" not in subtree and "998" not in subtree, "user data leaked"
    assert subtree["408"]["_class"] == "Task"
    assert "1414" in subtree and "1418" in subtree, "datasets missing"
    assert "20001" in subtree, "testcase missing"
    ds = set(digests)
    for d in ["dig-grader", "dig-header", "dig-st-th", "dig-st-en", "dig-att",
              "dig-in-101", "dig-out-101", "dig-in-201", "dig-out-201",
              "dig-in-202", "dig-out-202"]:
        assert d in ds, "missing digest " + d
    missing_tid, _, _ = m.build_subtree(objs, "no_such_task")
    assert missing_tid is None
    print("OK")
  PY

  test 'build_subtree keeps the task subtree, drops users, collects all digests' do
    out, err, status = Open3.capture3('python3', '-c', PYTEST, SCRIPT.to_s, FIXTURE.to_s)
    assert status.success?, "python failed:\n#{err}"
    assert_includes out, 'OK'
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/engine/converters/extract_task_filter_test.rb`
Expected: FAIL — python cannot load the (nonexistent) script.

- [ ] **Step 3: Write the extractor**

`script/cms_extract/extract_task.py`:

```python
#!/usr/bin/env python3
"""Extract ONE task from a live CMS instance as a portable bundle.

Runs ON the CMS server as the cms user, streamed over ssh (never installed):

    ssh HOST sudo -n -u cms /home/cms/cms_venv/bin/python3 - TASKNAME \
        < script/cms_extract/extract_task.py > bundle.tar

Wraps the official cmsDumpExporter for ALL serialization (structure-only,
no submissions / user-tests / print jobs; the full-instance structure dump
measured ~45 s on c2, which is fine per clone, so no -c contest scoping is
needed). Adds only what official tooling cannot do:
  * single-task subtree filter -- Users/Participations (password hashes)
    never enter the bundle and never leave the server
  * digest-selective blob fetch via cms FileCacher (blobs live in the DB;
    there is no on-disk file store on c2)

stdout: tar stream of bundle/ (task.json + files/<digest>)
stderr: progress log            exit: 0 ok, 2 usage, 3 task not found
Read-only against CMS. Work dir is 0700 under /tmp and removed on exit.
Consumed by app/engine/converters/cms_dump_converter.rb (bundle_version 1).
"""
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

BUNDLE_VERSION = 1
VENV = os.environ.get("CMS_VENV", "/home/cms/cms_venv")


def log(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def build_subtree(objects, task_name):
    """Return (task_id, subtree, digests) for the named task.

    Pure function over the dump's object map (no CMS imports) so it is
    unit-testable off-server. Only the task row and its statements,
    attachments, datasets, managers, and testcases enter the subtree.
    """
    task_ids = [k for k, v in objects.items()
                if v.get("_class") == "Task" and v.get("name") == task_name]
    if not task_ids:
        return None, None, None
    tid = task_ids[0]
    task = objects[tid]
    subtree = {tid: task}
    digests = []
    for sid in task.get("statements", {}).values():
        subtree[str(sid)] = objects[str(sid)]
        digests.append(objects[str(sid)]["digest"])
    for aid in task.get("attachments", {}).values():
        subtree[str(aid)] = objects[str(aid)]
        digests.append(objects[str(aid)]["digest"])
    for did in task.get("datasets", []):
        ds = objects[str(did)]
        subtree[str(did)] = ds
        for mid in ds.get("managers", {}).values():
            subtree[str(mid)] = objects[str(mid)]
            digests.append(objects[str(mid)]["digest"])
        for tcid in ds.get("testcases", {}).values():
            tc = objects[str(tcid)]
            subtree[str(tcid)] = tc
            digests.append(tc["input"])
            digests.append(tc["output"])
    return tid, subtree, digests


def main():
    if len(sys.argv) != 2:
        log("usage: extract_task.py <task_name>")
        return 2
    task_name = sys.argv[1]
    work = tempfile.mkdtemp(prefix="cms_extract_")
    os.chmod(work, 0o700)
    try:
        # The exporter/FileCacher may create relative cache dirs -> keep them
        # inside the 0700 work dir.
        os.chdir(work)
        dump_dir = os.path.join(work, "dump")  # exporter refuses existing dirs
        log("[extract] official cmsDumpExporter (structure only, no submissions) ...")
        subprocess.run(
            [os.path.join(VENV, "bin", "cmsDumpExporter"),
             "-F", "-S", "-U", "-P", dump_dir],
            check=True, stdout=sys.stderr, stderr=sys.stderr)
        with open(os.path.join(dump_dir, "contest.json")) as f:
            dump = json.load(f)
        dump_version = dump.get("_version")
        objects = {k: v for k, v in dump.items() if not k.startswith("_")}
        tid, subtree, digests = build_subtree(objects, task_name)
        if tid is None:
            names = sorted(v["name"] for v in objects.values()
                           if v.get("_class") == "Task")
            log("ERROR: task '%s' not found. %d tasks exist, e.g.: %s"
                % (task_name, len(names), ", ".join(names[:10])))
            return 3
        log("[extract] task id %s: %d objects, %d unique blobs"
            % (tid, len(subtree), len(set(digests))))

        bundle = os.path.join(work, "bundle")
        files_dir = os.path.join(bundle, "files")
        os.makedirs(files_dir)
        with open(os.path.join(bundle, "task.json"), "w") as f:
            json.dump({"bundle_version": BUNDLE_VERSION,
                       "dump_version": dump_version,
                       "task_id": tid,
                       "objects": subtree},
                      f, ensure_ascii=False, indent=1)

        log("[extract] fetching blobs via FileCacher ...")
        from cms.db.filecacher import FileCacher  # venv import; server only
        fc = FileCacher()
        for dig in sorted(set(digests)):
            src = fc.get_file(dig)
            with open(os.path.join(files_dir, dig), "wb") as out:
                shutil.copyfileobj(src, out)
            src.close()

        log("[extract] streaming bundle to stdout ...")
        with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tar:
            tar.add(bundle, arcname="bundle")
        sys.stdout.buffer.flush()
        log("[extract] done")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the filter test and a syntax check**

Run: `bin/rails test test/engine/converters/extract_task_filter_test.rb`
Expected: PASS.
Run: `python3 -m py_compile script/cms_extract/extract_task.py && echo SYNTAX-OK`
Expected: `SYNTAX-OK` (3.6 compatibility is by construction: no f-strings, no walrus).

- [ ] **Step 5: Commit**

```bash
[ "$(hg log -r . --template '{activebookmark}')" = "master" ] && \
hg add script/cms_extract/extract_task.py test/engine/converters/extract_task_filter_test.rb && \
hg commit script/cms_extract/extract_task.py test/engine/converters/extract_task_filter_test.rb \
  -m "feat(cms-clone): server-side task extractor wrapping official cmsDumpExporter (subtree filter + FileCacher blob fetch)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" || echo "NOT ON master — use the clone route (Global Constraints)"
```

---

### Task 5: `rake cms:clone` + config plumbing + CHANGELOG

The operator surface tying the units together, plus the ignored per-host config and its committed sample. Ends with the full offline test sweep.

**Files:**
- Create: `lib/tasks/cms.rake`
- Create: `config/cms_remote.yml.sample`
- Modify: `.gitignore` (append one line)
- Modify: `CHANGELOG.md` (one bullet under `[Unreleased]` → `### Added`)

**Interfaces:**
- Consumes: `script/cms_extract/extract_task.py` invocation contract (Task 4); `Converters::CmsDumpConverter#convert`/`#problem_meta` (Task 2); `ProblemImporter#import_dataset_from_dir` + `#errors` + `#problem` + `#dataset` (existing).
- Produces: `rails "cms:clone[<task_name>]"`.

- [ ] **Step 1: Write the rake task**

`lib/tasks/cms.rake`:

```ruby
# CMS -> cafe task clone. Spec: docs/superpowers/specs/2026-08-02-cms-clone-import-design.md
# Connection settings: config/cms_remote.yml (NOT committed; see the .sample)
# or ENV CMS_SSH_HOST / CMS_REMOTE_PYTHON.
namespace :cms do
  desc 'Clone a task from the remote CMS. Usage: rails "cms:clone[task_name]"'
  task :clone, %i[name] => :environment do |_t, args|
    require 'open3'
    require 'tmpdir'

    name = args[:name].to_s
    abort 'Usage: rails "cms:clone[<task_name>]"' if name.blank?
    # Task name goes onto the remote command line -- keep it shell-inert.
    abort "Task name '#{name}' contains unsupported characters" unless name.match?(/\A[\w.\-]+\z/)

    cfg_file = Rails.root.join('config', 'cms_remote.yml')
    cfg = File.exist?(cfg_file) ? YAML.safe_load(File.read(cfg_file), symbolize_names: true) : {}
    host   = ENV['CMS_SSH_HOST'] || cfg[:host]
    python = ENV['CMS_REMOTE_PYTHON'] || cfg[:python] || '/home/cms/cms_venv/bin/python3'
    abort 'Set CMS_SSH_HOST or create config/cms_remote.yml (see config/cms_remote.yml.sample)' if host.blank?

    if (existing = Problem.find_by(name: name))
      puts "NOTE: problem '#{name}' already exists (id #{existing.id}); " \
           'the import will ADD a new dataset generation to it (live dataset unchanged).'
    end

    script = Rails.root.join('script', 'cms_extract', 'extract_task.py')
    Dir.mktmpdir('cms_clone_') do |tmp|
      tar_path = File.join(tmp, 'bundle.tar')
      puts "Extracting '#{name}' from #{host} ..."
      cmd = ['ssh', '-o', 'BatchMode=yes', host,
             'sudo', '-n', '-u', 'cms', python, '-', name]
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
      abort 'Extraction failed (see [cms] lines above).' unless status&.success?

      system('tar', '-xf', tar_path, '-C', tmp) or abort 'could not untar bundle'
      bundle_dir = File.join(tmp, 'bundle')
      staging = File.join(tmp, 'staging')

      conv = Converters::CmsDumpConverter.new
      res = conv.convert(bundle_dir, staging)
      res[:log].each      { |l| puts "  #{l}" }
      res[:warnings].each { |w| puts "  WARNING: #{w}" }
      if res[:errors].any?
        res[:errors].each { |e| warn "  ERROR: #{e}" }
        abort 'Conversion rejected the task; nothing was imported.'
      end

      meta = conv.problem_meta
      pi = ProblemImporter.new
      log = pi.import_dataset_from_dir(staging, meta[:name], full_name: meta[:full_name])
      puts(log.is_a?(Array) ? log.map { |l| "  #{l}" }.join("\n") : "  #{log}")
      abort "Import errors: #{pi.errors.join('; ')}" if pi.errors.any?

      # Carry the CMS dataset name onto the live dataset (importer auto-names it).
      pi.dataset.update(name: meta[:live_dataset_name]) if meta[:live_dataset_name].present?
      puts "Cloned '#{meta[:name]}' -> problem id #{pi.problem.id} " \
           "(#{pi.problem.datasets.count} dataset(s); available=false until you enable it)."
    end
  end
end
```

- [ ] **Step 2: Write the config sample and ignore the real file**

`config/cms_remote.yml.sample`:

```yaml
# CMS clone connection settings. Copy to config/cms_remote.yml (which is
# NOT committed -- listed in .gitignore) and adjust per host.
# ENV overrides: CMS_SSH_HOST, CMS_REMOTE_PYTHON.
host: nattee@c2.thailandoi.org          # ssh target with passwordless `sudo -u cms`
python: /home/cms/cms_venv/bin/python3  # CMS venv python on that host
```

Append to `.gitignore` (after the `/config/worker.yml` line, matching its per-host-config pattern):

```
/config/cms_remote.yml
```

- [ ] **Step 3: Smoke the surface offline**

Run: `bin/rails "cms:clone[]"` → expect the usage abort.
Run: `CMS_SSH_HOST= bin/rails "cms:clone[foo]"` with no `config/cms_remote.yml` → expect the "Set CMS_SSH_HOST" abort.
Run: `bin/rails "cms:clone[bad name]"` → expect the unsupported-characters abort.

- [ ] **Step 4: CHANGELOG bullet**

Under `## [Unreleased]` → `### Added` (create the subsection if absent, ordered Added/Changed/Fixed/Security), citing the revs this project lands as:

```markdown
- CMS task clone: `rails "cms:clone[task]"` imports a Batch task (all datasets)
  straight from a live CMS server over ssh — official dump subtree + selective
  blob fetch on the server, converted to the cafe package layout and imported
  through the trusted importer. GroupMin (count and regex forms) maps to
  `group_min`; Communication/OutputOnly, file-I/O, and GroupMinPrereq tasks are
  rejected with clear messages (per-dataset skip when non-active). Connection
  settings live in `config/cms_remote.yml` (gitignored; sample committed). (revs …)
```

- [ ] **Step 5: Full offline sweep**

Run: `bin/rails test test/engine/converters/`
Expected: all green (fixture + converter + integration + filter tests).
Run: `bin/rails check`
Expected: green (or only failures demonstrably pre-existing on master — compare with a run before this project's commits if anything fails).

- [ ] **Step 6: Commit**

```bash
[ "$(hg log -r . --template '{activebookmark}')" = "master" ] && \
hg add lib/tasks/cms.rake config/cms_remote.yml.sample && \
hg commit lib/tasks/cms.rake config/cms_remote.yml.sample .gitignore CHANGELOG.md \
  -m "feat(cms-clone): cms:clone rake surface + per-host connection config

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" || echo "NOT ON master — use the clone route (Global Constraints)"
```

---

### Task 6: Operator gate — live clone of `mar2025_eatingfish` (manual, with dae)

The session deliverable. Run against the live server; nothing here is CI.

**Files:** none (operator steps; results recorded in the session/ledger notes).

**Interfaces:**
- Consumes: everything above, plus dae's dev environment (dev server + a judge worker running, per `bin/dev` on the parked `chula_cp` working copy or dae's usual setup).

- [ ] **Step 1: Config** — `cp config/cms_remote.yml.sample config/cms_remote.yml` (defaults already point at c2).
- [ ] **Step 2: Clone** — `bin/rails "cms:clone[mar2025_eatingfish]"`. Expect `[cms]` progress lines (exporter ~45 s, then blob fetch ~160 MB for 42+40 testcases, then tar transfer), converter log (2 datasets: `fish_rev2` live + the sibling), warnings for the skipped `en` statement, and a final "Cloned ... problem id N".
- [ ] **Step 3: Inspect in UI** — problem exists, unavailable; statement PDF opens (Thai); 2 datasets with GroupMin groups `7/19/13/23/27/11` weights over 42 testcases (live); managers `grader.cpp` + `eatingfish.h`; attachment `eatingfish-public.zip` downloads.
- [ ] **Step 4: Judge the model solution** — extract `eatingfish.cpp` from the attachment zip, submit as admin through the UI (dev judge running), expect **100** with all-`P` grader_comment. Benign `T→P`/`x→P`-style variance is impossible here (faster dev box, generous limit); any non-P testcase is a real finding — investigate before calling the gate passed.
- [ ] **Step 5: Record** — note the clone + judge outcome (and any warnings worth backlog entries) in the session report to dae; leave the problem in the dev DB (unavailable).

## Plan Self-Review Notes

- **Spec coverage:** extractor-wraps-official-exporter (Task 4), secrets never leave (filter test asserts User/Participation exclusion), digest-selective fetch (Task 4), converter mapping table incl. GroupMin both forms + lexicographic order (Task 2), multi-dataset active→root/others→fragments (Tasks 2–3), reject/skip matrix (Task 2 tests), statement primary-language rule (Task 2), attachment bundling + glob-collision guard (Task 2), rake surface + env/yml config + no committed secrets (Task 5), operator E2E gate incl. model-solution judging (Task 6), CHANGELOG (Task 5). Spec's "idempotent re-run" is implemented as the importer's actual semantics — re-clone ADDS a dataset generation (live untouched); the rake task says so out loud (Task 5 NOTE line). Dump-version pinning fails loud (Task 2 test).
- **Deviation from spec (documented):** no `-c <contest>` scoping — the task's contest isn't known before the dump is read, and the full-instance structure-only dump is ~45 s / 4 MB (measured). Recorded in the extractor docstring.
- **Type consistency:** `convert → {log:, warnings:, errors:}` and `problem_meta → {name:, full_name:, live_dataset_name:}` used identically in Tasks 2, 3, 5; bundle schema identical in Tasks 1, 2, 4.
