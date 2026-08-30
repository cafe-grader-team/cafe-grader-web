# Multi-Dataset Export/Import (Design)

**Date:** 2026-07-16 · **Status:** approved design, pending plan
**Decided with:** dae. Follows `doc/problem-import-export-design-2026-07-14.md` (Package 1) and the Mode A validation work.

## Goal

Today cafe exports/imports only a problem's **live** dataset (`ProblemExporter` uses `@problem.live_dataset`; the importer creates one dataset). Add the ability to export **all** of a problem's datasets and re-import them, via an **additive, backward-compatible** `.zip` format — with a live-only/all toggle on export (operator API + rake **and** a web control) and an import that always takes in whatever datasets the package contains.

## Non-goals

- No change to Italian/CMS export (that format is single-dataset per task; multi-dataset is a cafe↔cafe concern). CMS interop remains Package 2.
- No new grading behavior. Only the live dataset grades submissions; additional datasets are carried for archival/migration/versioning. The Mode A replay harness already covers live-dataset grading fidelity; this feature is validated by a **structural** round-trip test.

## The `.zip` format — additive

The root of the package continues to describe the **live** dataset in exactly today's flat layout. Additional datasets are *added* under `datasets/`, and the root `config.yml` gains one optional key.

```
config.yml                      # root: problem fields + LIVE dataset fields + testcases:{}  (UNCHANGED)
                                #   + NEW optional key:  additional_datasets: [<name>, <name>]
testcases/  checker/  managers/  initializers/  data_files/   # the LIVE dataset (unchanged)
statement.pdf  description.md  attachment/  model_solutions/   # problem-scoped (unchanged, root only)
datasets/                                                      # NEW, present only in "all" exports
  <dataset_name_parameterized>/
    config.yml                  # THIS dataset's fields + testcases:{} + dir keys (a per-dataset fragment)
    testcases/  checker/  managers/  initializers/  data_files/
  <dataset_name_parameterized>/
    …
```

- **Problem-scoped** artifacts (statement, attachment, description, tags, model solutions) live only at root — they belong to the Problem, not a Dataset.
- **Dataset-scoped** artifacts (testcases, checker, managers, initializers, data_files, and the dataset fields `time_limit`, `memory_limit`, `score_type`, `score_param`, `evaluation_type`, `main_filename`, `initializer_filename`) appear once per dataset: at root for the live one, under `datasets/<name>/` for the rest.
- `additional_datasets` lists the subdir names (parameterized dataset names) so the importer knows what to read without globbing.

### Backward compatibility (the core requirement)

1. **Old `.zip`** (no `additional_datasets`, no `datasets/`) → new importer imports the live dataset exactly as today. ✓
2. **New live-only export** (default) → **semantically identical (same files + same parsed config; YAML key order may differ) to today's output** — no `additional_datasets` key, no `datasets/` dir. Old importers and the CMS/Italian path are unaffected. ✓
3. **New all-datasets export** → an old importer reads the live dataset from root and silently ignores the unknown `additional_datasets` key and the `datasets/` dir (graceful degradation, no crash). ✓

## Exporter changes (`app/engine/problem_exporter.rb`)

The dataset-scoped methods currently hardcode `@main_dir` + `@ds` + the shared `@options`. Refactor so a dataset can be exported to an arbitrary directory with its own options hash:

- Extract **`export_dataset_files(ds, dir, opts)`** — writes `ds`'s `testcases/`, `managers/`+`checker/`, `initializers/`, `data_files/` under `dir`, and populates `opts` with the testcases hash, the dir keys, the `DATASET_OPTION_FIELDS`, and `ds_name`. (This is `export_testcases`/`export_managers_checker`/`export_initializers`/`export_data_files` + the dataset half of `export_options`, parameterized on `(ds, dir, opts)` instead of `@ds`/`@main_dir`/`@options`.)
- `export_problem_to_dir(problem, base_dir:, zip: false, all_datasets: false)`:
  - problem-scoped writes at root as today (`export_pdf`, `export_attachment`, `export_description`, `export_solutions`), plus problem fields + tags + markdown into the root `@options`.
  - live dataset → `export_dataset_files(live, @main_dir, @options)` (root).
  - if `all_datasets`: for each `@problem.datasets` except the live one, `export_dataset_files(ds, @main_dir/'datasets'/ds.name.parameterize, frag)` and write `frag.to_yaml` to that subdir's `config.yml`; collect the subdir names into `@options[:additional_datasets]`.
  - write root `config.yml` from `@options` (now also carrying `additional_datasets` when present).
- Guard: two datasets whose names parameterize to the same string → append `-2`, `-3` (dir-name collision), and log it.
- `dump_problems` and `Problem#export` gain the `all_datasets:` pass-through (default false).

## Importer changes (`app/engine/problem_importer.rb`)

- `import_dataset_from_dir(dir, name, …, do_additional_datasets: true)`: after the existing root import + `read_options`, call `import_additional_datasets` when the option is set.
- **`import_additional_datasets`**: for each name in `@options[:additional_datasets]`, read `datasets/<name>/config.yml`, create a new **non-live** `Dataset` on `@problem`, and read that subdir's dataset-scoped files into it (testcases, checker, managers, initializers, data_files) applying the fragment's dataset fields. Reuse the dataset-scoped read logic (extract a `read_dataset_files(base_dir, dataset, options)` from the current `read_testcase`/`read_checker`/`read_cpp_extras`/`read_initializers`/`read_data_files`, which today lean on `@base_dir`/`@dataset`/`@options`).
- The live dataset stays whatever the root import set it to (unchanged). Additional datasets are added, never made live.
- Re-import onto an existing problem: additional datasets are matched by **name** — an existing same-named dataset is updated in place (mirroring how root re-import updates the live dataset), else a new one is created. (Keeps re-import idempotent rather than piling up duplicate datasets.)

## Web + operator surface

- **Operator (A):** `ProblemExporter#export_problem_to_dir(..., all_datasets: true)`, `Problem#export(all_datasets: true)`, and a rake flag — e.g. `rake "problems:export[name,all]"` or an `ALL_DATASETS=1` env on the existing dump path.
- **Web (B):** the problem page's existing **Download archive** button becomes a small dropdown — **"Download (live dataset)"** (default, current behavior, unchanged URL/format) and **"Download (all datasets)"**. `download_archive` takes an optional `all_datasets` param (admin-only, as today) and passes it to `@problem.export`. The live-only entry stays the default so muscle memory and any existing links keep producing the CMS-safe single-dataset zip.

## Tests

- **Structural round-trip (all datasets):** a fixture problem with ≥2 datasets (distinct fields — different `time_limit`/`score_type`/testcase sets, a manager on one) → export `all_datasets: true` → re-import under a new name → assert **every** dataset round-trips (count, per-dataset fields, per-testcase code_name/num/group/group_name/weight/content, checker/managers filenames+bytes), and that the same dataset is live.
- **Live-only unchanged:** export `all_datasets: false` on the same problem → assert no `datasets/` dir and no `additional_datasets` key (byte-compatible with today).
- **Backward compat:** the existing single-dataset fixtures still import unchanged; an all-datasets zip fed to the *root-only* path (`do_additional_datasets: false`) imports just the live dataset.
- **Re-import idempotency:** importing an all-datasets package twice onto the same problem does not duplicate the additional datasets.
- **Controller:** `download_archive?all_datasets=1` produces a zip containing `datasets/`; the plain call does not.

## CHANGELOG

`### Added` — multi-dataset export (operator `all_datasets:` + rake + a "Download (all datasets)" option on the problem page) and import; the zip format is a backward-compatible superset (old zips import unchanged; live-only export is byte-identical to before).

## Implementation-time notes

- Confirm `Dataset#name` uniqueness scoping per problem so name-based additional-dataset matching on re-import is well-defined (`get_next_dataset_name` already avoids collisions on create).
- The exporter refactor must keep the live-only output byte-identical — pin it with the "live-only unchanged" test before touching `export_problem_to_dir`.
- CMS/Italian export path (Package 2) will consume only the live dataset; nothing here should make `additional_datasets` leak into that format.
