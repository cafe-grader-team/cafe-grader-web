# Changelog

All notable changes to this project are recorded here. Format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `[Unreleased]` section at the top accumulates changes between releases.
When a release is cut: rename it to `[X.Y.Z] — YYYY-MM-DD`, bump
`APP_VERSION`, and (optionally) tag the commit in hg/git.

## [Unreleased]

## [4.3.3] — 2026-05-19

### Added

- **Help drawer on `/problems/:id/edit`** — a Bootstrap offcanvas panel
  opened by a labeled `? Help` button in the page header. Documents the
  Detail-card fields, dataset structure, operations, and links out to
  the project wiki. Pattern codified in `CLAUDE.md` as
  "context-dependent help" (inline knowledge cards on index/overview
  pages; offcanvas drawers on edit/detail pages).
- **`Live` badge in the dataset selector** marking the currently-live
  dataset. The `Set as live` button is shown only on non-live ones, so
  the state is never ambiguous.
- **PDF Export sub-section** on the Description tab with an explicit
  Delete button (uses a hidden-form pattern so it can't produce
  nested `<form>` tags).
- **CU pink + KU yellow-green gradient `C` favicon and navbar brand
  mark.** Single asset (`app/assets/images/icon.svg`) serves both the
  browser-tab favicon and the in-app brand mark — single source of
  truth.
- **`CHANGELOG.md`** itself (this file).
- **Dev-environment additions**: `listen` gem with
  `ActiveSupport::EventedFileUpdateChecker` replaces polling-based file
  watching (fixed multi-second WSL2 cascading-turbo-frame slowness);
  `rack-mini-profiler` + `stackprof` for in-app perf diagnostics.
- **`doc/backlog.md`** as the project's convention for tracking
  deferred design work (linked from `CLAUDE.md`).

### Changed

- **General tab of the problem editor** reorganized into 5 labeled
  sections (Identity / Statement & Files / Categorization / Visibility
  & Listing / Grading & Compilation), with `permitted_lang` moved into
  Grading & Compilation. Column split changed from 5/7 to 6/6 to give
  the form more room.
- **Description tab**: yellow info-card removed (content moved into the
  help drawer), textarea grown to 20 monospaced rows, dead `markdown`
  / `url` fields cleaned up.
- **Hint tab**: alert-wrapped selector replaced with a flat row,
  redundant labels dropped, Add/Delete separated, body field now a
  textarea, friendlier empty state.
- **Dataset selector**: alert wrapper stripped, redundant labels
  dropped, dropdown gets select2 styling, Add + Set-as-live remain
  visible while Rejudge + Delete move behind a `⋮` dropdown (per
  CLAUDE.md's Progressive Condensation rule).
- **Section headers unified** across both the problem form column AND
  the dataset card (Settings/Testcases/Files tabs) using
  `h5 fw-bold text-body-emphasis pb-2 border-bottom`.
- **`compilation_type` field** switched from a `<select>` (with an
  off-feeling blank option) to vertically-stacked styled radio buttons.
- **Server-mutating clicks across dataset views** migrated from legacy
  `link_to … data: { turbo_method: … }` to `button_to` and
  hidden-form + HTML5 `form="..."` patterns per CLAUDE.md.
- **Per-testcase row actions** redesigned as three visible icon-only
  buttons (input / output / delete) with tooltips, sharing three
  hidden forms (Flavor B); the testcase table also picks up the
  project's standard admin-table classes.
- **Per-file row actions** in the Files tab (managers / checker /
  initializers / data files) redesigned same way.
- **Grammar / wording sweep** across the problem editor: tooltip
  rewrites, confirm-dialog standardization ("Really delete X?" →
  "Delete X? This cannot be undone."), `score_type` option text
  rephrased, sentence-case consistency, etc.
- **`finance` Material Symbol replaced with `query_stats`** wherever it
  meant Statistics — clearer metaphor.
- **`llm.yml.SAMPLE` refreshed** to mirror the real config's schema,
  documentation, and environments.

### Fixed

- **AuditLog `destroy` callback** no longer raises "Auditable must
  exist" — the polymorphic `belongs_to` is now declared
  `optional: true`, matching the helper's already-correct treatment of
  destroyed records.
- **Quick-create on `/problems`** now refreshes the list. The previous
  `turbo_stream.append` of a `datatable:reload` event had no listener
  on this page; switched to a `redirect_to` with `status: :see_other`.
- **select2 dropdowns** now reliably fire `change` events into
  Stimulus. select2 v4 dispatches events through jQuery's event system,
  which doesn't always reach native `addEventListener` listeners that
  Stimulus' `data-action` relies on. A bridge in
  `init_ui_component_controller.js` listens for the jQuery
  `select2:select` event and re-dispatches it as a native `change`.
- **`simple_form_for` data-attribute collision**: passing both a
  top-level `data:` and an `html: { data: { … } }` silently dropped the
  top-level one. The dataset and hint selectors now consolidate
  everything into `html: { data: { … } }`. Footgun documented in
  `CLAUDE.md`.
- **Tooltip data-attribute encoding**: Rails' `link_to`-and-friends
  JSON-encode nested `data: { bs: { toggle: … } }` hashes (HAML
  flattens them with hyphens). Several tooltips on problem/contest/
  dataset edit pages were silently broken because the rendered attribute
  was `data-bs='{"toggle":"tooltip"}'` instead of `data-bs-toggle="tooltip"`.
  Migrated to flat `data: { bs_toggle: … }` form across the codebase.
- **WSL2 dev-mode cascading-turbo-frame slowness** (~2 s per concurrent
  request) diagnosed and fixed: the default polling
  `FileUpdateChecker` runs `Dir.glob` on every request and concurrent
  calls serialize on WSL2 inode locks. Switched to the evented variant
  (see Added).
- **`Language` model**: `name` is now enforced unique (via DB index) and
  immutable after create (via model validator). A migration
  idempotently re-runs `Language.seed`, so newly-added entries (e.g.
  `viva`) land on existing installations via `db:migrate` without a
  manual `db:seed` step. Language seed itself uses
  `find_or_create_by!` / `update!` so partial failures raise instead
  of leaving half-created rows.

### Internal

- Convention notes added to `CLAUDE.md`: flat data-attribute form for
  Bootstrap data attrs; offcanvas help-trigger labeling exception;
  context-dependent help-pattern split; backlog pointer; development
  environment (file watcher and profiler).
- Project-history memory entries added (branch workflow, simple_form
  data-collision gotcha, grep-existing-pattern-first principle).
- `doc/backlog.md` seeded with deferred items (help-pattern
  unification, AuditLog destroy test, orphan `contests/_contest_help`
  partial, drawer-content density rewrite).
