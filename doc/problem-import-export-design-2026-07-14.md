# Problem Import/Export — Audit, Round-Trip Parity, CMS Interop (Design)

**Date:** 2026-07-14 · **Status:** approved design, pending implementation plan
**Decided with:** dae (brainstorming session 2026-07-13/14)

## Goals

1. **Package 1 — harden the trusted path.** The existing zip import (`ProblemImporter`)
   is the trusted, familiar flow. Audit it for missing-field and correctness bugs,
   make `ProblemExporter` a true inverse, and pin both with round-trip tests.
2. **Package 2 — CMS interop.** Import CMS-ecosystem task packages (Italian
   `task.yaml` format and TPS `problem.json` format) and export cafe problems as
   Italian-format packages consumable by `cmsImportTask`.

Reference CMS instance: 10.44.7.1 (`ssh`, then `sudo su cms`), CMS 1.5.1,
loaders `italy_yaml`/`polygon`/`tps`, custom score type `GroupMinPrereq`
(github.com/Marszpace/cmsGroupMinPrereq). Live inventory: Batch (majority),
Communication (~5), OutputOnly (2); scores GroupMin / GroupMinPrereq / Sum.

## Non-goals (this project)

- No judge-side capability work: Communication (manager + FIFO), OutputOnly
  grading, file-I/O tasks, and GroupMinPrereq scoring are **rejected at import
  with clear messages** and recorded in `doc/backlog.md` as future projects.
  Eventually cafe intends to support everything CMS supports; each such project
  later flips its converter rule from "reject" to "map".
- No TPS *export* (TPS is an authoring system; export target is Italian only).
- No **architectural rewrite** of the trusted importer (Approach C / in-memory
  IR — backlog, only if supported formats multiply). "Rewrite" here means
  replacing `ProblemImporter`'s direct directory→DB structure with a
  parse→IR→materialize pipeline. It does **not** mean the importer's code is
  frozen — the targeted, in-place bug fixes of Package 1 are the heart of this
  project and are fully in scope.

## Key decisions

| Decision | Choice |
|---|---|
| Export semantics | **Portable package**: authored content round-trips; instance-local state does not |
| Package format | Current cafe zip layout + `config.yml` stays canonical; grows keys as cafe grows capabilities |
| CMS import formats | Italian (`task.yaml`) + TPS (`problem.json`) |
| CMS export format | Italian only |
| Task-type scope | Batch only; others rejected + backlog |
| GroupMinPrereq tasks | **Rejected** (no silent score degradation) |
| UI surface | Existing import page with format auto-detect; "Export for CMS" beside existing archive download; rake tasks for bulk |
| Architecture | **Approach A**: format converters produce a cafe-format staging dir; the one trusted `ProblemImporter` is the only DB-writing path. Export mirrors: trusted exporter dir → Italian converter |
| scorer.rb group weight | **Keep `.min`**; fix comment + `doc/dataset-scoring-and-evaluation.md` to say *min*; do NOT flip to max |

## Round-trip contract (Package 1)

Authored content that MUST survive import → export → re-import:

| Entity | Fields / attachments |
|---|---|
| Problem | `name`, `full_name`, `description` (markdown text), `markdown` flag, `submission_filename`, `task_type`, `compilation_type`, `permitted_lang`, tags, statement PDF, attachment |
| Dataset (live) | `name`, `time_limit`, `memory_limit`, `score_type`, `score_param`, `evaluation_type`, `main_filename`, `initializer_filename`, checker, managers, initializers, **data_files** |
| Testcase | `code_name`, `num` (order), `group`, `group_name`, `weight`, input, answer |
| Model solutions | submissions with `tag: :model` — language + source filename + source |

Deliberately instance-local (NOT in the package): `available`, `date_added`,
`view_testcase`, `view_submission`, `allow_hint`, `difficulty`, `test_allowed`,
`url`, `full_score` (derived), non-live datasets, submission history, stats.

**New finding during design:** `Dataset#data_files` ("additional files when
running") are neither exported nor imported today — symmetric hole. Added to the
contract: exporter writes `data_files/`, importer reads it (config-key mirrored
like initializers).

## Package 1 — fixes

Tests come first (characterization), then each fix lands red→green.

### Tests

`test/engine/problem_import_export_test.rb` (or split importer/exporter):

- **Import characterization:** import `test/problem_examples/fibo` (+ a new
  richer fixture with checker, managers, initializers, data_files,
  `description.md`, tags, `score_param`, group weights) → assert every field in
  the contract table.
- **Round-trip parity:** import → export → re-import under a new name →
  field-by-field compare per the contract; instance-local fields explicitly
  excluded.
- Converter tests are Package 2.

### Importer (`app/engine/problem_importer.rb`)

1. `code_name_regex` dead-variable: `codename_mc` computed, `mc` used
   (lines ~30–31 and ~48–49). Apply `codename_mc[1]` when it matches.
2. `read_solutions` filename split garbles names: `basename.split('_')` array
   used as length. Fix: split on **first** underscore → lang prefix + rest
   (`cpp_fibo.cpp` → lang `cpp`, source `fibo.cpp`).
3. Imported model solutions get `tag: :model` (today they lose model status, so
   the *next* export drops them). Attribution: keep `User.first` default but
   accept a `user:` kwarg (controller passes `@current_user`).
4. Blank `full_name` param falls back to `name` (today an empty form field
   overwrites `full_name` with blank).
5. `.md` statement import also sets `markdown` flag: from `config.yml` key when
   present; legacy zips with a `.md` but no key default `markdown: true`.
6. `score_param` added to `d_options`.
7. `data_files` import (new dir convention `data_files/`).
8. Mixed-weights warning: when the package declares different weights within
   one group under `group_min`, emit a loud import-log warning (CMS semantics:
   one weight per group; heterogeneity is an authoring error).

### Controller (`problems_controller.rb`)

9. `import_testcases` with `target == 'replace'` and an invalid dataset id
   currently falls through to *creating a new dataset*; make it an error.
   Also pass `do_attachment: false` (testcases-only flow must not touch the
   problem-level attachment; initializers stay — dataset-scoped).

### Exporter (`app/engine/problem_exporter.rb`)

10. Write `description.md` when `Problem#description` present; `markdown` flag
    into `config.yml` p_options.
11. `score_param` added to `d_options`; export `data_files/`.
12. `zip: fasle` typo → `false` (currently `ProblemExporter.dump_problems`
    crashes with NameError).
13. `OptionConst::DEFAULT[:file][:statement]`: `statment.pdf` → `statement.pdf`
    (import globs `*.pdf`, old zips unaffected).
14. `download_archive` guards no-live-dataset → friendly alert, not a 500.
15. **Anti-drift:** move the shared `p_options` / `d_options` symbol lists into
    `OptionConst` so importer and exporter read one constant (today two
    hand-synced lists with "MUST MATCH" comments).

### Security

16. Shell safety: argv-form `Open3.capture3('unzip', file, '-d', dest)` and
    `('zip', '-r', out, '.')` — no interpolated shell strings (problem name
    currently reaches the command line).
17. Extraction dir derived via `parameterize` (no user-controlled path
    segments); post-extract containment check (every extracted entry resolves
    under the destination — zip-slip defense independent of unzip version).
18. Authorization: `do_import` uses `find_or_create_by(name:)` → a group editor
    can silently overwrite any same-named problem. New rule: if the name
    exists, require edit rights on that problem (admin keeps re-import-updates
    behavior; non-admin gets "name already taken" unless editor of it).

### Cleanups

19. `scorer.rb` `group_min`: keep `.min` behavior; rename the misleading
    `max_weight` variable, fix the comment and
    `doc/dataset-scoring-and-evaluation.md` to say **min**. Informational
    data-hygiene scan (run against production before deploy; expected 0, as in
    dev):

    ```ruby
    Testcase.joins(:dataset).where(datasets: {score_type: 1})
            .group(:dataset_id, :group).having("COUNT(DISTINCT weight) > 1").count
    ```
20. Delete dead `Problem.create_from_import_form_params` (references
    `TestdataImporter`, which now lives only in `script/old_scripts/`; zero
    callers). Verify whether `extract_params_and_check` is shared before
    removing it too.

## Package 2 — CMS interop (Approach A)

### Pipeline

```
import:  upload.zip → unzip → sniff format
           task.yaml    → CmsItalianConverter ─┐
           problem.json → TpsConverter        ─┼→ cafe staging dir → ProblemImporter (no format-specific branches added)
           otherwise    → (existing path, no conversion)
export:  ProblemExporter → cafe dir → CmsItalianConverter.reverse → Italian dir → zip
```

- Converters live in `app/engine/converters/`; interface
  `convert(src_dir, dest_dir) → {log:, warnings:, errors:}`. Pure dir→dir
  transforms; testcase files **hardlinked** (same FS as `judge_raw_path`) to
  avoid duplicating IOI-sized test sets.
- All validation and rejection happens in the converter, before the trusted
  importer runs. Converter log/warnings merge into the existing import log page.
- Both marker files present → error. The testcases-into-existing-problem page
  stays cafe-format only.

### Rejection rules (clear message + backlog pointer)

| Condition | Detection |
|---|---|
| Communication task | Italian: `cor/manager*` / graders indicating manager process; TPS: `"type" != "Batch"` |
| OutputOnly task | Italian: `output_only: True` in task.yaml; TPS: type |
| File-I/O task | Italian: non-empty `infile`/`outfile` (cafe judge is stdio-only) |
| Prereq scoring | any package expressing prerequisite score structure |
| (export) evaluation type not CMS-runnable | see export eligibility matrix below |

### Italian → cafe mapping

| Italian package | cafe |
|---|---|
| `task.yaml` `name` | `problem.name` |
| `title` | `full_name` |
| `time_limit` (s, float) | `dataset.time_limit` |
| `memlimit` / `memory_limit` (MiB) | `dataset.memory_limit` |
| `n_input` | cross-check testcase count (warn on mismatch) |
| `input/input%d.txt` + `output/output%d.txt` | testcases, `code_name` = index |
| `gen/GEN` `# ST: <w>` blocks | groups with weight `w` per case; `score_type: group_min` |
| no ST markers | `score_type: sum`, weight 1 |
| statement PDF (`statement/` or `testo/`) | statement (multi-language: prefer `th`, then `en`, else first + warn) |
| `sol/grader.*` | managers + `compilation_type: with_managers` |
| `sol/solution.*` | model solution (`tag: :model`) |
| `att/*` | attachment (>1 file → bundle into one zip + warn) |
| `check/checker*` / `cor/correttore*` | checker + `evaluation_type: custom_cms` |

### TPS → cafe mapping

| TPS package | cafe |
|---|---|
| `problem.json` `name` / `title` | `name` / `full_name` |
| `type` | must be `Batch` (else reject) |
| `time_limit` (s) / `memory_limit` (MB) | dataset limits |
| `tests/*.in` + `*.out` | testcases; codename preserved (e.g. `1-01`) |
| `subtasks.json` (`score`, per-test assignment) | groups + weights, `group_min`; `samples` subtask → weight 0 |
| `checker/` | checker + `custom_cms` |
| `statement/*.pdf` | statement |
| `public/` | attachment bundle |
| `solutions.json` model-verdict entry | model solution |
| `gen/`, `validator/` | skipped with log line (not silently) |

Exact per-test↔subtask assignment source (`subtasks.json` globs/regex vs
`tests/mapping` vs `gen/data`) verified at implementation time against dae's
real packages.

### cafe → Italian export mapping

| cafe | Italian package |
|---|---|
| `name` / `full_name` | `task.yaml` `name` / `title` (+ sane defaults: `n_input`, `public_testcases: ""`, `token_mode: disabled`, `infile: ""`, `outfile: ""`) |
| limits | `time_limit`, `memlimit` |
| testcases (by `num`) | `input/input0..N-1.txt`, `output/output0..N-1.txt` — renumbered contiguously; codename↔index map emitted in log |
| `group_min` groups | `gen/GEN` `# ST:` blocks, multiplier = group weight; groups must be contiguous by `num` (else reject with message) |
| `sum`, uniform weights | no ST markers (CMS Sum; loader sets param 100/N) |
| `sum`, non-uniform weights | singleton-group GroupMin, multipliers scaled to total 100 + warn |
| checker | `check/checker.cpp` **source** + log note: compile to `check/checker` before `cmsImportTask` (no cross-compile at export) |

**Export eligibility by `evaluation_type`** (CMS can only run its own checker
protocol or white-diff; local usage counts from dev DB 2026-07-15):

| cafe evaluation_type | exportable? | note |
|---|---|---|
| `default` (507 probs) | ✓ | CMS white-diff comparator |
| `exact` (0) | ✓-ish | CMS white-diff is not byte-exact; unused locally — warn |
| `custom_cms` (4) | ✓ | same protocol; checker source shipped |
| `custom_cafe` (22) | ✗ reject | protocol mismatch (CORRECT/INCORRECT + score/10) — backlog: adapter shim |
| `relative` (11) | ✗ reject | implemented in Ruby judge-side — backlog: C++ comparator |
| `postgres` (2), `custom_cms_raw` (6) | ✗ reject | no CMS equivalent |

| managers | `sol/grader.*` (main manager) + companion headers in `sol/` |
| model solutions | `sol/solution.<ext>` (first per language; extras logged) |
| statement | `statement/statement.pdf` |
| attachment | `att/<filename>` |
| `description` md, tags, initializers, data_files | no Italian slot — skipped with log line |

### Surfaces

- **Web:** import page unchanged visually (sniff decides); problem page gains
  "Export for CMS (Italian)" beside the existing archive download.
- **Rake:** `problems:import_cms[path]` (single package or dir of packages,
  auto-detect per package) and `problems:export_cms[names,dest]` for
  camp-sized batches.

### Testing

- Mini Italian + TPS fixture packages beside `fibo` in `test/problem_examples/`.
- Converter unit tests: pure dir→dir, no Rails.
- One end-to-end per format through the real importer, asserting the Package 1
  field surface.
- Golden-file test for Italian export.
- Behavioral gate: the submission-replay harness (next section) — structural
  tests run in CI; replay runs as an operator gate.

## Validation harness — submission replay (operator gate, not CI)

Differential testing with real submissions as oracle: replay a submission
corpus through both graders and diff **per-testcase** outcomes (keyed via the
converter's codename↔index map, so a mismatch names the testcase and group).

### Modes

- **Mode A — cafe→cafe (Package 1 gate).** Import → export → re-import as a
  scratch problem; rejudge the source problem's submissions against **both**
  (rejudge-vs-rejudge, both graded now on the same judge — historical scores
  are NOT the oracle, so judge drift since submission time can't pollute the
  diff). Scores must match exactly; only borderline-TLE jitter tolerated.
- **Mode B — CMS→cafe (Package 2 import gate).** Extract sources + official
  per-testcase outcomes from the CMS DB (read-only: `SessionGen` queries /
  `cmsExportSubmissions`), import the task via converter, replay locally, diff
  against CMS-recorded results. Corpus: 5 importable tasks, **1,348
  submissions** (choreography 734, watergun 202, potential 147,
  colonyguards 138, voltage 127).
- **Mode C — cafe→CMS (Package 2 export gate).** Export → `cmsImportTask` into
  a **scratch contest** on 10.44.7.1 → replay cafe submissions via
  `cmsAddSubmission` → diff. Writes to the live CMS box: **runs only with
  dae's explicit per-run go-ahead**, never touches existing contests, cleanup
  via `cmsRemoveSubmissions` + `cmsRemoveContest`. Custom checkers are
  compiled on the CMS box as part of setup.

### Two-pass protocol (kills timing noise)

1. **Correctness pass** — replay against a dataset copy with time limit ×3.
   Per-testcase outcomes must match **exactly**; any diff is a real bug.
   This pass gates the release.
2. **Timing pass** — replay with authored limits; report classified by the
   established convention: `T→P` / `x→P` benign, `P→T` expected on a slower
   judge (reported, not failed), everything else → investigate.

Report buckets per task: exact / benign-timing / environment (CE from
compiler-version differences — real finding, not an import bug) /
**investigate**. Float outcomes compared with epsilon.

### Curated export set (mode A; spans the feature axes)

| Feature axis | Candidate (submission count) |
|---|---|
| default eval + multi-group sum | ex00e2 (7,441) |
| custom_cafe checker | a58_proj_algo (7,472) |
| custom_cms checker | a68_q4a_normal_puzzle (1,259) |
| relative eval | ex07m1_knapsack (5,694) |
| group_min | a57_m4_gaa (3,731) |
| group_min + custom_cafe | a67_q4a_strange_house (2,523) |
| with_managers + attachment | d58_q1_erase_many (7,403) |
| initializers | db_proc_contest (2,213) |
| postgres eval | SQL-Quiz-2024-2-Q9 (190) |
| raw_sum + custom_cms_raw | rubiks_race_2 (1,256) |

`data_files`: zero real usage in dev DB — fixture-only coverage.
Mode C uses the exportable subset of this list (default/custom_cms eval only),
final pick when the eligibility check runs.

### Mechanics

- Rake surface: `problems:replay_validate[...]` + a read-only CMS extraction
  script; report written per run.
- Replayed submissions belong to a dedicated user (e.g. `replay_bot`) against
  unavailable scratch problems; deleted after the run — no stat pollution.
- Workflow: stratified sample (~50/task across the score range) while
  developing; full corpus overnight as the final gate.
- Lasting value: the same harness serves any future judge/scorer change
  (regression grading diffs).

## Error handling

- Converter `errors` abort before the importer runs → shown as the import
  page's error list (web) or stderr + nonzero exit (rake).
- `warnings` and `log` merge into the existing import log page — same trusted UX.
- Export rejections (`raw_sum`, non-contiguous groups) → toast alert (web) /
  stderr (rake), nothing written.

## Backlog additions (`doc/backlog.md`)

- Communication task support in cafe judge (manager process + FIFOs) → then map on import/export.
- OutputOnly grading support → then map.
- GroupMinPrereq scoring in cafe scorer (`score_param` holds prereq DAG) → then map.
- File-I/O task support (or permanent rejection decision).
- Checker protocol adapter so `custom_cafe` checkers can export to CMS.
- C++ relative comparator (CMS-side equivalent of `lib/checker/relative.rb`).
- Group-weight uniformity validation in dataset edit UI.
- Approach-C IR refactor if supported formats multiply beyond Italian+TPS.

## Implementation-time verifications

- `engine/checker.rb`: does the judge expect checker **source** (compiles it)
  or a prebuilt binary? Determines what Italian/TPS checker artifact to prefer.
- `extract_params_and_check` — shared or dead along with
  `create_from_import_form_params`?
- TPS per-test↔subtask assignment file, against real packages.
- `task.yaml` minimum key set accepted by cmsImportTask 1.5.1 (verify on
  10.44.7.1 with the italy_yaml loader source).
