# Cafe-Grader 2023 Migration Workflow

Tools for migrating the legacy filesystem-based judge data (under `old-judge/ev/`) into the current DB-backed schema, plus a sanity-check pipeline for verifying that submissions still grade correctly after migration.

## Files in this directory

| File | Purpose |
|------|---------|
| `migrate_tasks_v2.rb` | Main migration script. Imports legacy testcases / managers / checkers, attaches PDFs, rescales submission points to a 0-100 scale. |
| `testcase_to_activestorage_v2.rb` | Migrates legacy `Testcase.input` / `Testcase.sol` text columns into Active Storage `inp_file` / `ans_file` blobs. Different code path from `migrate_tasks_v2` — used only when starting from a DB snapshot whose testcases live in DB columns rather than on disk. |
| `sanity_capture.rb` | Captures baseline submissions (legacy points + grader_comment) into `sanity_baseline.json`. |
| `sanity_verify.rb` | Rejudges captured submissions, polls until done, classifies and reports score drift. |
| `sanity_compare.rb` | Read-only re-comparison using the existing baseline JSON, no queueing. Use when `sanity_verify` timed out but the worker actually finished, or when you've already rejudged manually. |
| `rejudge_affected.rb` | Queues rejudge for submissions belonging to "manager-affected" problems (lib/ dir or custom compile-script-referenced subdir). Used after the manager-attachment fix. Default mode targets only baseline subs (fast verification); `MODE=all` targets every submission for those problems (production rejudge). |
| `test_v2.rb` | Test harness for `migrate_tasks_v2`. Exercises one example per checker branch on a curated set of 9 ev directories and verifies idempotency. |
| `migrate_anomalies.log` | Append-mode anomaly log written during a migration run. |
| `sanity_baseline.json` | Output of `sanity_capture.rb`, input to `sanity_verify` / `sanity_compare`. |
| `sanity_report_<timestamp>.json` | Per-run output of `sanity_verify` / `sanity_compare`. |

## Prerequisites

1. **Legacy data path.** Constants at the top of `migrate_tasks_v2.rb`:
   ```ruby
   LEGACY_JUDGE_DIR  = Pathname.new('/home/dae/cafe-grader/old-judge')
   EV_DIR            = LEGACY_JUDGE_DIR + 'ev'
   JUDGE_SCRIPTS_DIR = LEGACY_JUDGE_DIR + 'scripts'
   TASK_PDF_DIR      = Rails.root.join('data', 'tasks')
   ```
   `JUDGE_SCRIPTS_DIR/templates/check.{text,float,integer}` must exist or `read_default_checker` raises ENOENT on the first problem with a `script/check`.

2. **DB state.** Problem rows for ev/ entries must already exist with matching names (the script doesn't create them). Verify before running:
   ```bash
   bin/rails runner 'puts "#{Problem.count} problems in DB"'
   ```

3. **Schema up to date** (Active Storage tables, etc.):
   ```bash
   bin/rails db:migrate
   bin/rails db:migrate:queue
   ```

## Migration workflow

### Phase 1 — capture baseline (optional, for sanity check)

If you want to verify with `sanity_verify` later, capture the baseline first. Can run pre- or post-migrate; post-migrate is required for `KIND` filtering.

```bash
LIMIT_PROBLEMS=200 RANDOM=1 KIND=custom_cafe,group_min \
  bin/rails runner script/migrate_2023/sanity_capture.rb
```

### Phase 2 — run the migration

```bash
bin/rails runner script/migrate_2023/migrate_tasks_v2.rb 2>&1 | tee /tmp/migrate.log
```

Type `yes` at the confirmation prompt. The script:

1. Per-problem (1031 problems on this DB):
   - Skip if Problem already has a `default` dataset linked as `live_dataset` (idempotent).
   - Repair if a `default` dataset exists but is orphaned (previous run crashed mid-import).
   - Import testcases from `<EV_DIR>/<name>/test_cases/N/{input,answer}-N.txt`.
   - Parse `all_tests.cfg` for time/memory limits, group/score config.
   - Read managers via `ProblemImporter`.
   - Classify and attach checker (see Checker classification below).
2. Globally:
   - Attach PDF statements from `data/tasks/<id>/<filename>` (skip if already attached).
   - `Language.seed`.
   - `GraderProcess.delete_all`.
   - Rescale legacy `Submission.points` to 0-100, set `Problem.full_score = 100` as sentinel.

Ends with a SUMMARY block tallying everything.

### Phase 3 — language remap

`Language.seed` adds the new naming convention but doesn't remap existing submissions.

```bash
bin/rails runner '
  remap = { "c++" => "cpp" }
  remap.each do |old_name, new_name|
    old = Language.find_by(name: old_name)
    new_lang = Language.find_by(name: new_name)
    next unless old && new_lang && old.id != new_lang.id
    n = Submission.where(language_id: old.id).update_all(language_id: new_lang.id)
    puts "remapped #{n} subs: #{old_name}(#{old.id}) -> #{new_name}(#{new_lang.id})"
  end
'
```

Then scan for any other legacy languages still referenced:

```bash
bin/rails runner '
  seeded = %w[c cpp pas ruby python java php haskell digital rust go postgres archive text viva]
  used = Submission.distinct.pluck(:language_id).compact
  legacy = Language.where(id: used).where.not(name: seeded)
  legacy.each { |l| puts "id=#{l.id} name=#{l.name.inspect} (#{Submission.where(language_id: l.id).count} subs)" }
'
```

### Phase 4 — sanity check (optional)

Start the judge worker, verify it registered:

```bash
bin/rails runner 'puts GraderProcess.where("updated_at > ?", 1.minute.ago).pluck(:host_id, :pid, :status).inspect'
```

If you have many concurrent workers, bump Puma threads first (otherwise worker → API calls serialize):

```bash
RAILS_MAX_THREADS=10 bin/dev
```

Dry-run the verify to see what would queue:

```bash
DRY_RUN=1 bin/rails runner script/migrate_2023/sanity_verify.rb
```

Real run:

```bash
bin/rails runner script/migrate_2023/sanity_verify.rb 2>&1 | tee /tmp/verify.log
```

If `sanity_verify` times out (e.g., slow worker, large sample) but the worker eventually finishes, run `sanity_compare.rb` to re-read results without re-queueing:

```bash
bin/rails runner script/migrate_2023/sanity_compare.rb
```

## Re-run safety

`migrate_tasks_v2.rb` is idempotent across all sections:

| Step | Behavior on re-run |
|------|--------------------|
| Per-problem migration | Skipped if `live_dataset_id` already points at a `default` dataset for that problem. Repaired if dataset is orphaned. |
| PDF attachment | Skipped if statement already attached. |
| `Language.seed` | `find_or_create_by` + `update`. |
| `GraderProcess.delete_all` | Trivially idempotent. |
| Submission rescale | Skipped via `full_score != 100` sentinel. |

`live_dataset_id` is set as the **last** step of `do_dir`. If a per-problem step crashes, the dataset stays orphaned and the next run repairs it.

## Checker classification

For each ev problem, `read_checker_from_ev` classifies `script/check` into one branch. Counts seen on full corpus (1031 problems):

| Branch | Approx count | What's attached | `evaluation_type` set |
|--------|-------------:|-----------------|----------------------|
| Matches `templates/check.text` (with shebang normalize) | 886 | nothing | `default` |
| Matches `templates/check.float` | 5 | nothing | `relative` |
| Matches `templates/check.integer` | 3 | nothing | `default` (collapses) |
| `REAL_CHECK_SCRIPT = "..."` → ELF binary | 101 | the binary | `custom_cafe` |
| `REAL_CHECK_SCRIPT = "..."` → script (shebang) | 15 | the script | `custom_cafe` |
| `REAL_CHECK_SCRIPT = "..."` → MISSING file | 4 | nothing (logged anomaly) | `custom_cafe` |
| Custom inline (variant of template, >50% line overlap) | 14 | the wrapper | `custom_cafe` |
| Custom inline (true outlier) | 1 | the wrapper | `custom_cafe` |
| No `script/check` | 2 | nothing | column default (`default`) |

## Manager files (`lib/` convention)

About 40 ev problems put their grader-side support files in `<ev>/lib/`:

- `<problem>.h` — the public header students compile against (e.g. `blindwalk.h`).
- A main `.cpp`/`.c` that calls into student code. Often `grader.cpp` but sometimes `<problem>_private.cpp` (pandemic), `<problem>libpriv.cpp` (househouse), `sockslib.cpp`, etc.
- Stale or model-implementation files that are NOT compiled with the student's submission (e.g. blindwalk has `blindwalk.cpp` and `bwalk_graph.cpp` in lib/ but the legacy compile script only links `grader.cpp`).

`ProblemImporter#read_cpp_extras` only globs `*.h` non-recursively from the root, and its main detection only matches the hardcoded list `[main.cpp, main_grader.cpp, grader.cpp]`. Both gaps are filled by `migrate_tasks_v2.rb#attach_managers_from_compile`, which uses **`script/compile`** as the source of truth.

**Parsing rules** (`parse_compile_refs`): the regex captures `/judge/ev/<problem>/<subdir>(/<subdir>)*/<file.ext>` triples — handling four real variants:

| Variant | Example | Captured |
|---|---|---|
| Single subdir | `/judge/ev/blindwalk/lib/grader.cpp` | `(blindwalk, lib, grader.cpp)` |
| `script/`-based | `/judge/ev/balkan11_decrypt/script/grader.cpp` | `(balkan11_decrypt, script, grader.cpp)` |
| Cross-problem refs | `_s4` problem points at `/judge/ev/o63_jun17_malwarex/lib/grader.cpp` | `(o63_jun17_malwarex, lib, grader.cpp)` |
| Nested subdirs | `/judge/ev/ioi95_wires/script/wirelib/wirelib.cpp` | `(ioi95_wires, script/wirelib, wirelib.cpp)` |

Extension alternation is ordered LONGEST FIRST (`cpp\|cc\|hpp\|hxx\|hh\|c\|h`) so `grader.cpp` doesn't get captured as `grader.c`.

**Attachment rules:**

1. Each `(problem, subdir)` from compile becomes a directory to scan, resolved against `<ev_root>/<problem>/<subdir>`. Cross-problem refs hit the sibling problem's actual files.
2. Falls back to `<self>/lib/` if compile has no refs and that dir exists.
3. **Headers** (`.h .hpp .hxx .hh`) attached unconditionally (include path).
4. **Source** files (`.c .cpp .cc`) attached only if listed in compile (avoids stale model code like blindwalk's `blindwalk.cpp` / `bwalk_graph.cpp`).
5. Skip backups (`~`, `.bak`, `.org`, `.mod\d+`), already-attached files, and files whose stem matches the REAL_CHECK_SCRIPT target.
6. **`dataset.main_filename`** set/overridden to the compile-referenced `.cpp`/`.c` (preferring `.cpp` if both exist).
7. **`Problem.submission_filename`** defaults to `'student.cpp'` for the legacy ev convention (student source compiled as a separate translation unit alongside grader; `student.h` produces compilation_error since the file would be passed to g++ as a top-level translation unit).
8. Cross-problem ref where the resolved path doesn't exist on disk → anomaly `compile_ref_path_missing` logged, no fatal failure.

Run output: `attached managers: <list>` and `set main_filename = ...` per problem. Cross-problem refs show as `<other_problem>/<subdir>/<file>` so they stand out in the log.

### Patching already-migrated problems

The new logic only fires during fresh per-problem imports. If you've already migrated and want to apply the manager fix to existing datasets without redoing everything, reset just the affected problems (those with a `lib/` directory **or** a custom `script/compile` that references grader source files) and re-run migrate:

```bash
bin/rails runner '
  EV = "/home/dae/cafe-grader/old-judge/ev"
  affected = Set.new
  # problems with lib/
  Dir["#{EV}/*/lib"].each { |d| affected << File.basename(File.dirname(d)) }
  # problems whose compile references /judge/ev/<name>/<subdir>/<file>
  Dir["#{EV}/*/script/compile"].each do |cf|
    next unless File.read(cf, mode: "rb") =~ %r{/judge/ev/[\w.+-]+/(?:lib|script)/[\w.+-]+\.(?:c|cpp|cc|h|hpp)}i
    affected << File.basename(File.dirname(File.dirname(cf)))
  end
  affected.each do |name|
    p = Problem.find_by(name: name); next unless p
    ds = p.datasets.find_by(name: "default"); next unless ds
    p.update_column(:live_dataset_id, nil)
    ds.destroy
    puts "reset #{name}"
  end
  puts "total reset: #{affected.size}"
'
bin/rails runner script/migrate_2023/migrate_tasks_v2.rb 2>&1 | tee /tmp/migrate_patch.log
```

The migrate run only re-processes those problems thanks to the orphan check; everything else is skipped.

After the patch run, rejudge the affected submissions so they pick up the corrected manager set:

```bash
# Verification rejudge: only baseline subs in affected problems (fast).
bin/rails runner script/migrate_2023/rejudge_affected.rb

# After the worker drains:
bin/rails runner script/migrate_2023/sanity_compare.rb
```

Or for a production rejudge of every submission for those problems:

```bash
MODE=all bin/rails runner script/migrate_2023/rejudge_affected.rb 2>&1 | tee /tmp/rejudge.log
```

Both modes prompt for `yes` before queuing (set `YES=1` to skip the prompt).

## grader_comment letter convention

Per-testcase result letters (one char per testcase, in `Dataset#testcases.display_order`):

| char | meaning |
|------|---------|
| `P` | Pass (full credit) |
| `T` | Time limit exceeded |
| `x` | Invalid operation (segmentation fault) or memory limit exceeded |
| `-` | Wrong answer |
| `s` | Partial credit on this testcase |

When diffing two grading runs (e.g. legacy vs migrated), only `T -> P` and `x -> P` transitions are usually benign (machine-speed / memory differences). Other transitions reflect real score changes worth investigating.

## Anomaly log

Written append-mode to `migrate_anomalies.log`. Entries are timestamped, key=value format. Categories:

| kind | meaning |
|------|---------|
| `repairing_orphan_dataset` | Previous run crashed mid-import; re-creating dataset for this problem. |
| `missing_testcase_file` | `test_cases/N/` exists but `input-N.txt` or `answer-N.txt` is missing. Skipped, kept going. |
| `cfg_run_block_incomplete` | A `run X do ... end` block in `all_tests.cfg` had `tests` but no `scores` (or vice versa). Affected testcases keep import-time defaults. |
| `real_check_script_missing` | `REAL_CHECK_SCRIPT` named a target file that doesn't exist. Dataset gets `evaluation_type = custom_cafe` but no checker file. |
| `compile_ref_path_missing` | `script/compile` references a `<problem>/<subdir>` path that doesn't exist on disk (e.g., a typo in a cross-problem reference). Skipped. |

The end-of-run summary in `main` prints the path if any anomalies were logged. Clean it before a fresh test cycle:

```bash
rm -f script/migrate_2023/migrate_anomalies.log
```

## Sanity-check classification

`sanity_compare.rb` and `sanity_verify.rb` Phase 3 classify each entry into:

| classification | meaning | action |
|---------------:|---------|--------|
| `exact_match` | rejudge points within `TOLERANCE` of `expected_pct` | none, this is the pass case |
| `limits_resolved` | only `T -> P` or `x -> P` transitions in grader_comment | none, benign machine drift |
| `score_regression` | only `P -> not-P` transitions | investigate — testcase that used to pass is now failing |
| `mixed_changes` | both directions of transition | investigate |
| `other_to_pass` | `- -> P` or `s -> P` transitions | investigate — checker may have become more lenient |
| `compilation_error_regression` | rejudge couldn't even compile a submission that previously scored | **smoking gun: manager attachment broke** |
| `grader_error_regression` | rejudge ran but checker errored | checker attachment is wrong |
| `non_done_status` | rejudge stuck in `submitted` / `evaluating` | worker didn't finish |
| `score_mismatch` | fallback when baseline has no grader_comment | investigate |

The summary table breaks each classification down by `kind` (full vs partial submission).

## Configuration reference

### `migrate_tasks_v2.rb`

Edit constants at top:

```ruby
LEGACY_JUDGE_DIR  = Pathname.new('/home/dae/cafe-grader/old-judge')
EV_DIR            = LEGACY_JUDGE_DIR + 'ev'
JUDGE_SCRIPTS_DIR = LEGACY_JUDGE_DIR + 'scripts'
TASK_PDF_DIR      = Rails.root.join('data', 'tasks')
```

### `sanity_capture.rb`

| env var | default | meaning |
|---------|---------|---------|
| `LIMIT_PROBLEMS` | 200 | number of problems to sample (0 = all) |
| `RANDOM` | unset | when `1`, sample randomly instead of by id |
| `SUBS_PER_KIND` | 2 | full subs to capture + partial subs to capture (per problem) |
| `KIND` | unset | comma-separated `evaluation_type` and/or `score_type` values to filter on (requires post-migrate state) |

### `sanity_verify.rb`

| env var | default | meaning |
|---------|---------|---------|
| `TOLERANCE` | 0.01 | acceptable absolute delta in pct points |
| `POLL_INTERVAL` | 5 | seconds between status polls |
| `TIMEOUT` | 1800 | seconds before giving up on pending jobs |
| `DRY_RUN` | unset | `1` prints plan without queueing or waiting |

### `sanity_compare.rb`

| env var | default | meaning |
|---------|---------|---------|
| `TOLERANCE` | 0.01 | same meaning as in `sanity_verify` |

### `test_v2.rb`

| env var | default | meaning |
|---------|---------|---------|
| `RESET` | unset | `1` destroys 'default' datasets for the 9 example Problems before phase 1 |

## Common pitfalls

- **No color when piping through `tee`**: Rainbow auto-disables when stdout isn't a TTY. `migrate_tasks_v2.rb` forces `Rainbow.enabled = true` so it always prints color. Log files contain ANSI escapes — view with `less -R`.
- **Confirmation prompt invisible when piping**: `migrate_tasks_v2.rb` sets `$stdout.sync = true` so the banner flushes before `gets` blocks.
- **Stale `live_dataset_id` from old code path**: very early failures (the `o56_apr26_land`-class crash from a pre-fix run) may leave a problem with `live_dataset_id` set to a partially-imported dataset. Find and reset:
  ```bash
  bin/rails runner '
    Problem.joins(:datasets).where(datasets: {name: "default"}).find_each.select do |p|
      ds = p.datasets.find_by(name: "default")
      ds && p.live_dataset_id == ds.id && !ds.checker.attached? &&
        File.exist?("/home/dae/cafe-grader/old-judge/ev/#{p.name}/script/check")
    end.each { |p| puts p.name }
  '
  ```
- **Multiple judge workers serializing on Puma threads**: bump `RAILS_MAX_THREADS=10` (or higher) when running parallel workers; the DB pool follows automatically.

## Recommended full re-cycle

```bash
# 1. Stop running services. Confirm backup is at hand.

# 2. Reset DB
bin/rails db:drop && bin/rails db:create
mysql -u root grader < /path/to/original_backup.sql
bin/rails db:migrate
bin/rails db:migrate:queue

# 3. Clean stale artifacts
rm -f script/migrate_2023/migrate_anomalies.log
rm -f script/migrate_2023/sanity_baseline.json
rm -f script/migrate_2023/sanity_report_*.json

# 4. Migrate
bin/rails runner script/migrate_2023/migrate_tasks_v2.rb 2>&1 | tee /tmp/migrate.log

# 5. Language remap
bin/rails runner '
  o = Language.find_by(name: "c++"); n = Language.find_by(name: "cpp")
  Submission.where(language_id: o.id).update_all(language_id: n.id) if o && n && o.id != n.id
'

# 6. (Optional) save a post-migrate backup so future test cycles don't have to re-migrate
mysqldump -u root grader > /tmp/grader_post_migrate.sql

# 7. Capture sanity baseline (post-migrate, KIND filter usable)
LIMIT_PROBLEMS=200 RANDOM=1 KIND=custom_cafe,group_min \
  bin/rails runner script/migrate_2023/sanity_capture.rb

# 8. Start judge worker (whatever your normal command is). Verify:
bin/rails runner 'puts GraderProcess.where("updated_at > ?", 1.minute.ago).pluck(:host_id, :pid, :status).inspect'

# 9. Verify (rejudges, polls, classifies)
bin/rails runner script/migrate_2023/sanity_verify.rb 2>&1 | tee /tmp/verify.log

# 10. If verify times out but worker finishes later, re-read results:
bin/rails runner script/migrate_2023/sanity_compare.rb
```
