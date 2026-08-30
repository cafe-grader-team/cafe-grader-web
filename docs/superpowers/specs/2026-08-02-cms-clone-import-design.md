# CMS → cafe Task Clone (Import via CMS DB Extraction) — Design

**Date:** 2026-08-02 · **Status:** approved design, pending implementation plan
**Decided with:** dae. Successor to the CMS-import half of
`doc/problem-import-export-design-2026-07-14.md` (Package 2), reshaped for a
live-server source instead of packages on disk.

## Goal

One command on the cafe box clones a **Batch** task from the c2.thailandoi.org
CMS into the local grader:

```
rake "cms:clone[mar2025_eatingfish]"
```

v1 delivers a single-task clone (first target: `mar2025_eatingfish`), carrying
**all** of the task's datasets. The code is structured so a bulk/whole-contest
loop is a thin wrapper later, but v1 does not build it.

## Why this shape (recon findings, 2026-08-02)

- c2 (`ssh nattee@c2.thailandoi.org`) hosts CMS 1.4.dev3 in
  `/home/cms/cms_venv`, one `practice` contest (id 7) with 107 tasks (112 in
  DB total). **No task packages exist on disk** — tasks live only in the CMS
  Postgres DB, with file content in the DB-backed file store (there is no
  `/var/local/lib/cms/fs`; blobs resolve only through CMS `FileCacher`).
- `nattee` has passwordless `sudo -u cms` (set up 2026-08-02,
  `/etc/sudoers.d/nattee-cms`, runas-only grant). The `cms` user runs all CMS
  services, is in the `cmsuser` group, and therefore reads
  `/usr/local/etc/cms.conf` (DB creds) — verified: `cmsDumpExporter` as `cms`
  reaches the DB, and `FileCacher().get_file(digest)` returns real bytes for a
  manager and a testcase input.
- Therefore the source of truth is **CMS's own canonical representation**
  (dump-format JSON + digest-addressed blobs), not the Italian format the
  2026-07-14 design assumed. It is strictly richer (native `GroupMin` params
  vs. reconstructing `gen/GEN # ST:` markers) and needs no HTML scraping.
  (An authenticated AdminWebServer scrape was proven viable as a fallback
  channel during recon, but is not built.)
- **Why official tooling alone doesn't suffice** (verified on the box): CMS
  ships no task-level exporter — `cmsDumpExporter` is contest-scoped only
  (107 tasks, multi-GB with files), its structure dump always includes
  Users/Participations with password hashes (no `--no-users` flag exists),
  and no official CLI fetches selected blobs by digest. The extractor
  therefore **wraps** the official exporter rather than replacing it: all
  serialization is official; the custom glue is only task-scoping, secrets
  stripping, and digest-selective blob fetch.

## Architecture

```
[cafe box]  rake cms:clone[NAME]
   │  ssh nattee@c2 → sudo -n -u cms bash (streams script/cms_extract/extract_task.py)
   ▼
[c2, as cms]  official cmsDumpExporter -F -S -c <contest>  → /tmp/<run>/dump   (structure only, ~seconds)
              extract_task.py — pure JSON walk + FileCacher, READ-ONLY:
                picks the ONE task's subtree → task.json  (users/participations never enter it)
                resolves that task's digests → files/<sha1-digest>
   │  tars bundle to stdout → cafe box; /tmp/<run> (0700) removed in the same ssh run
   ▼
[cafe box]  CmsDumpConverter (Ruby, pure dir→dir)   → cafe staging dir
   ▼
ProblemImporter (existing, untouched)               → dev DB
```

Two isolated units with a dumb bundle between them; the trusted
`ProblemImporter` remains the **only** DB-writing path (Approach-A shape from
the 2026-07-14 design).

### Unit 1 — CMS-side extractor (`script/cms_extract/extract_task.py`)

- Lives in the cafe repo; **streamed** to the server per run (`python3 -` over
  ssh) — nothing installed on c2.
- **Wraps official machinery — it does not query the DB itself.** The run
  first invokes the official `cmsDumpExporter -F -S -c <contest>` (structure
  only, no submissions; ~seconds, 4 MB JSON for the whole box). The script
  then does two things CMS tooling cannot:
  1. **Task-subtree filter** (pure JSON walk, no DB): from `contest.json`,
     emit `task.json` = the official dump-format subtree for the ONE task —
     Task row, **all** its Datasets (task_type, task_type_parameters,
     score_type, score_type_parameters, limits, description, managers,
     testcases codename→digest map, `active` flag), Statements, Attachments.
     The dump's `_version` is carried through alongside `bundle_version: 1`.
     **No users, participations, or submissions** — password hashes never
     leave the server (the raw dump lives only in the 0700 run dir and is
     deleted in the same ssh invocation).
  2. **Digest-selective blob fetch** (~10 lines): `FileCacher().get_file()`
     for exactly that task's digests → `files/<digest>`.
- Read-only by construction (the official exporter + file reads). FileCacher's
  cache dir is pointed inside `/tmp/<run>` so server cleanup is one `rm -rf`,
  executed in the same ssh invocation even on failure (`trap`-style cleanup).

### Unit 2 — cafe-side converter (`app/engine/converters/cms_dump_converter.rb`)

- First occupant of the `converters/` home reserved by the 2026-07-14 design.
  Interface as specced there: pure `convert(bundle_dir, staging_dir)` →
  `{log:, warnings:, errors:}`. No CMS/SQLAlchemy coupling; unit-testable from
  a committed fixture bundle.
- Emits the **canonical cafe staging dir** consumed by `ProblemImporter`,
  using the multi-dataset zip layout (2026-07-16 design): active CMS dataset →
  root layout (becomes the live dataset); each other dataset →
  `datasets/<name>/` + root `additional_datasets` key.
- All validation/rejection happens here, before the importer runs.

## Field mapping (grounded in the real `mar2025_eatingfish` dump)

| CMS | cafe | Note |
|---|---|---|
| Task `name` / `title` | `Problem#name` / `full_name` | title may be Thai text |
| `submission_format: ["eatingfish.%l"]` | `submission_filename` | single `%l` entry expected for Batch; anything else → warn (exact cafe filename semantics verified at impl time) |
| `statements` + `primary_statements` | statement PDF | primary language wins; others logged as skipped (cafe holds one statement) |
| `attachments` | attachment | >1 file → bundled into one zip + warn (existing cafe rule) |
| Dataset `description` | `Dataset#name` | e.g. `fish_rev2`; blank → generated name |
| `active_dataset` | live dataset | root of the staging layout |
| `time_limit` (s) / `memory_limit` (MB) | dataset limits | direct |
| `task_type: "Batch"` | required | else reject (active) / skip dataset (non-active) |
| `task_type_parameters[0]`: `"grader"` / `"alone"` | `compilation_type` `with_managers` / normal | |
| `task_type_parameters[1]`: `["",""]` | stdio — OK | non-empty infile/outfile → file-I/O reject/skip |
| `task_type_parameters[2]`: `"diff"` / `"comparator"` | `evaluation_type` `default` / `custom_cms` + checker | comparator manager (`checker`) split out of managers/ |
| `managers` | `managers/` | |
| `score_type: "Sum"` | `sum` | |
| `score_type: "GroupMin"` | `group_min` | both param forms, below |
| `score_type: "GroupMinPrereq"` | reject / skip | no silent score degradation (standing decision) |
| Testcase `codename` / `input`,`output` digests | `code_name` / `num` / input+answer files | order = codename sort (CMS's own ordering) |

**GroupMin parameters — both CMS forms map onto grammar cafe already has**
(rev 1856 testcase-config work):

- `[[points, N], …]` — integer N = testcase count, consumed in
  **codename-sorted order** (eatingfish: `[[7,7],[19,6],[13,6],[23,5],[27,6],[11,12]]`,
  counts sum to 42 = testcase count ✓) → contiguous groups, group weight = points.
- `[[points, "regex"], …]` — codename regex, `re.match` (start-anchored)
  semantics → cafe's codename-regex grouping grammar directly.

**Explicitly skipped with a log line** (instance-local or no cafe slot): token
settings, `max_submission_number` / `max_user_test_number`, `score_mode`,
`score_precision`, per-testcase `public` flags, non-primary statements.

## Rejection / skip rules

Converter-level, clear message + backlog pointer, nothing written:

| Condition | Active dataset | Non-active dataset |
|---|---|---|
| non-Batch `task_type` | **reject task** | **skip dataset** + warning |
| file-I/O (non-empty infile/outfile) | **reject task** | **skip dataset** + warning |
| `GroupMinPrereq` | **reject task** | **skip dataset** + warning |

These mirror the approved non-goals (Communication, OutputOnly, file-I/O,
prereq scoring live in `doc/backlog.md`); each future capability project flips
its rule from reject to map. `custom_cms` checkers are accepted — cafe
supports that protocol.

## Surface & configuration

- **Rake only**: `cms:clone[name]`. The web import page stays cafe-format-only
  (standing decision). Bulk later = thin loop over the same units.
- Connection settings (ssh target, venv path, python path) from env or an
  **hgignored** `config/cms_remote.yml`; no server names or credentials
  committed to the repo.
- Importing user = admin (as the existing import path). Re-running the clone
  updates the same-named problem via the importer's existing re-import
  semantics (idempotent; additional datasets match by name per the
  multi-dataset design).

## Error handling

Each stage fails loud and distinctly:

- ssh/extract failure → stderr passthrough, nonzero exit, nothing written
  locally; server tmp cleaned by the same ssh run even on failure.
- Converter `errors` → printed, staging dir discarded, importer never runs.
  A partial bundle cannot half-import — the importer starts only after the
  converter validates the full staging dir.
- Importer errors → its existing log surface.

## Testing

- **Converter unit tests** against a committed, trimmed fixture bundle
  (eatingfish-shaped, few small testcases): every mapped field asserted —
  name/full_name, limits, `with_managers` + managers, `group_min`
  groups/weights from integer params, a regex-param case, dataset-name
  mapping, multi-dataset layout (root + `datasets/` + `additional_datasets`),
  skip/reject matrix (non-Batch, file-I/O, GroupMinPrereq; active vs
  non-active). `test-groupminprereq` on c2 provides a real reject fixture.
- **End-to-end operator gate (= session deliverable)**: clone
  `mar2025_eatingfish` into the dev DB; verify in the UI; submit the model
  solution (in the attachment zip) through the real judge → full score.
- **Mode-B replay** (diff cafe verdicts vs CMS-recorded outcomes over the real
  submission corpus) remains the deep follow-up validation, not a blocker.

## Deliberately out of scope (v1)

- Bulk/whole-contest clone loop (structured-for, not built).
- cafe→CMS export (Mode C) and the Italian/TPS file-package converters —
  still worthwhile later for packages-on-disk sources; this session's source
  is the DB.
- Web UI for CMS clone.
- Judge capability work (Communication, OutputOnly, GroupMinPrereq, file-I/O)
  — unchanged backlog items.

## Implementation-time verifications

- `submission_format` `%l` → cafe `submission_filename` exact semantics
  (extension handling) against `Problem`/importer expectations.
- CMS GroupMin integer-count ordering: confirm codename sort in the GroupMin
  scorer source on c2 (`cmsGroupMinPrereq` sibling likewise for the reject
  detection).
- Checker artifact form when `evaluation_type: custom_cms` (source vs
  prebuilt) against `engine/checker.rb` expectations — not blocking for
  eatingfish (white-diff).
- FileCacher cache-dir override knob (constructor arg vs config) for the
  run-scoped tmp placement.
- `cmsDumpExporter` flag semantics on this version: whether `-G`
  (`--no-generated`) is safe/needed alongside `-F -S`, and the exact dump
  `_version` emitted (converter pins the version it understands and fails
  loud on others).
- `-c <contest>` speed vs full-box dump (probe ran full-box in ~45 s;
  contest-scoped should be faster — either is acceptable for v1).
