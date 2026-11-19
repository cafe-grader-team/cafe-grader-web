# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cafe-Grader is an online programming contest and assignment grading platform (used at Chulalongkorn University). Students submit code, which is automatically compiled and evaluated against test cases. Instructors manage problems, contests, groups, and view reports.

**Backlog of deferred work** lives in `doc/backlog.md` — design refactors, "someday" follow-ups, and decisions parked for a longer session. Check it when starting work in an area that might already have a planned change; add to it (don't bury in comments) when you defer something non-trivial. Inline `# TODO(scope): …` is fine for one-liners anchored to code; GitHub Issues are for scheduled/assigned work.

## User data stays out of this repo (standing rule, dae 2026-11-19)

This repo is public on GitHub (`github.com/nattee/cafe-grader-web`) and feeds the upstream project. **Never put personal data of any user into it** — not in code, comments, `doc/`, `docs/` specs and plans, test fixtures, commit messages, or GitHub issue/PR text. Personal data means logins (here = Chula student IDs), names, e-mail addresses, IP addresses tied to a person, a named or numbered individual's scores, waits or grades, submission source, viva transcripts and grade text. Write "a TA", "student A–G" or an aggregate count instead; when the list itself is needed, it goes in the private `~/cafe-grader/course-prep` repo and the doc points there. GitHub history cannot practically be scrubbed — the DS Quiz 1 postmortem showed seven students' logins in `doc/` for two months until 2026-11-19 — so the check comes before the commit: `test/no_user_pii_in_repo_test.rb` fails on any student-ID-shaped number (10 digits starting 4–7) or `@student.chula.ac.th` address in the project's own text files. It cannot see names, IPs or commit messages; those stay a review duty.

## Version Control

Local VCS is **Mercurial (hg)**, mirrored to **GitHub** via the **hg-git** extension. Use `hg` for all local operations (`hg status`, `hg commit`, `hg diff`, `hg push`). Issues and PRs live on GitHub — use the `gh` CLI for those (e.g., `gh issue close 51`).

**Branch workflow (`master` ↔ `chula_cp`).** Two long-lived bookmarks:
- **`master`** — trunk / the upstream-facing line. **All commits land here.**
- **`chula_cp`** — the Chula CP deployment branch. It carries deployment-specific config that is intentionally absent on master (e.g. the viva LLM services in `config/llm.yml` are `Llm::VivaTurnGenieAssist` / `Llm::VivaGradeGenieAssist` on chula_cp but blank on master). The dev server / Solid Queue worker should run **on chula_cp**, since those classes only exist there.
- **LLM-provider placement rule** (`doc/decisions.md` 2026-07-30): the branch is decided by *generality*, not abstractness — provider code any third-party deployment could use (self-hosted OpenAI-compatible endpoints, hosted aggregators like OpenRouter) lives on **master**, dormant until config activates it; only integrations that cannot work outside Chula (the ChulaGenie classes) live on chula_cp. Config values and secrets are per-deployment on either branch and never a reason to move code.

`chula_cp` **only ever receives batch-merges from master** — `hg update chula_cp && hg merge master && hg commit -m "merge master: …"` — bundled at logical stopping points, not per commit. **Never commit directly on `chula_cp`** (it skips master and creates divergence to clean up later). Before any `hg commit`, check the active bookmark (`hg log -r . --template '{activebookmark}\n'`); if `chula_cp` is active, `hg update master` first. One `hg push` mirrors both bookmarks via hg-git. Fuller context: the `/release` skill's conventions and `doc/llm-refactor-handoff-2026-05-07.md`.

## Changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/); the top `[Unreleased]` section accumulates changes between releases. **Maintain it incrementally — don't reconstruct it from the commit log at release time.** When a commit makes a *user- or operator-facing* change (new feature/report/endpoint, behavior change, bug fix, or a config/setup change that affects fresh clones), add a curated `### Added/Changed/Fixed/Security` bullet under `[Unreleased]` in the *same commit*, citing the rev. Skip pure internals — refactors, test-only changes, dependency bumps, and Claude/dev tooling (skills, editor config) that don't change app behavior (e.g. the `/release` and `/upstream-sync` skills are deliberately not in the changelog). Cutting a release is then just renaming `[Unreleased]` → `[X.Y.Z] — YYYY-MM-DD`; the `/release` skill's log-backfill step is a safety net, not the primary path.

## Viva & Assist Live Docs

Three documents track the two LLM-facing student features and must be kept current **in the same commit** as the change they describe, the way `CHANGELOG.md` is:

- `doc/Viva-History.md` — the change history (newest first): every commit that changes viva behavior, prompt text (conduct tags, briefings, kit files), the model or provider behind turns/grading, or access/alert policy gets an entry — *Problem observed → Change → Outcome/status*, with the rev/spec/kit ref. Prompt and kit edits live in the local `course-prep` hg repo; cite its rev too. When an entry supersedes an earlier one, mark the old one `SUPERSEDED` rather than deleting it.
- `doc/wiki/viva-authoring-guide.md` — the problem-setter guide. When a lesson from transcripts or an audit changes *how a viva should be written* (a new conduct rule, a rubric convention, a pitfall), update the relevant section and the pitfalls table; it is published to the upstream wiki as a verbatim copy, so keep it deployment-neutral (course-specific material only as examples, never a live problem's model answer).
- `doc/Assist-History.md` — the same for the submission-assist ("Codey") feature: every commit that changes assist behavior, the payload sent to the model, the prompt text (the `codey-*` tags, versioned in `course-prep/assist/`), the models or providers in the picker, or the price/access policy gets an entry; its "Numbers for reporting" table is refreshed from production when a measurement is redone. Studies get a pointer entry (next paragraph).

`doc/Viva-Exam.md` stays the platform reference (prompt assembly, lifecycle, policy) and keeps its own Decision Log for *design rationale*; the Histories are the *timeline*.

**Studies live in `course-prep`, never in this repo** (dae 2026-11-06). This repo is public on GitHub and feeds the upstream project, and a study's data (student code, transcripts, reader grades) can never be here, so the write-up goes with its data in the private `~/cafe-grader/course-prep` repo: model tests in `course-prep/model-eval/<date>-<what>/`, with their rows added to `course-prep/model-eval/README.md` (the running table of every model on every AI job); course and transcript studies in a dated folder of their own. The History entry carries the headline number and the course-prep path. The four study docs already in `doc/` (`assist-corpus-eval-2026-09-03`, `assist-gateway-read-2026-10-13`, `gateway-model-test-2026-10-29`, `dept-model-viva-test-2026-10-30`) stay as they are; add no new ones. Incident postmortems about the platform (e.g. `doc/exam-postmortem-2026-09-09-d69_q1.md`) still belong in `doc/`.

## Tech Stack

- **Ruby 3.4.4, Rails 8.0.0** (with `load_defaults 7.0`)
- **MySQL 8.0+ only** (Oracle MySQL or Percona; **MariaDB unsupported** — every table uses the `utf8mb4_0900_ai_ci` collation, which MariaDB lacks; enforced by `test/schema_collation_test.rb`, rationale in `doc/decisions.md`). Primary DB: `grader`, queue DB: `grader_queue`
- **Propshaft** asset pipeline, **ImportMap** for JS, **dartsass-rails** for CSS (no Node/yarn dependency)
- **Hotwire** (Turbo + Stimulus), jQuery (legacy), Bootstrap 5
- **HAML** templates
- **Solid Queue** for background jobs, **Solid Cache**, **Solid Cable**
- **Puma** web server with Thruster

## Development Commands

```bash
# Start all dev processes (server, CSS watcher, background queue)
bin/dev                          # uses Procfile.dev via foreman

# Or run individually:
bin/rails server                 # web server on port 3000
bin/rails dartsass:watch         # CSS compilation (dartsass-rails)
bin/rails solid_queue:start      # background job queue

# Database
bin/rails db:migrate             # primary DB migrations
bin/rails db:migrate:queue       # queue DB migrations (db/queue_migrate/)

# Tests
bin/rails check                  # EVERYTHING: minitest + RSpec API specs + swagger freshness (no system tests)
bin/rails test                   # all minitest tests (does NOT run the RSpec API specs)
bin/rails test test/models/      # test a directory
bin/rails test test/models/user_test.rb        # single file
bin/rails test test/models/user_test.rb:42     # single test by line
bin/rails test:system            # Capybara system tests

# Code quality
bundle exec rubocop              # linting (rubocop-rails-omakase)
bundle exec brakeman             # security analysis

# API specs & Swagger docs (RSpec + rswag)
bundle exec rspec spec/requests/api/v1/          # run API tests
bundle exec rails rswag:specs:swaggerize         # regenerate swagger/v1/swagger.yaml
bin/rails swagger:verify         # fail if swagger.yaml is stale (also part of `check`)
```

## Architecture

### Two Operating Modes

The system operates in either **contest mode** or **group mode** (configured via `GraderConfiguration`). This affects how problems are scoped and presented to users.

- **Server-global and exclusive.** `GraderConfiguration.contest_mode?` / `.indv_contest_mode?` / `.analysis_mode?` all read the same single site-wide config key (`SYSTEM_MODE_CONF_KEY`) — the *entire* site is in one mode at a time, never per-contest, per-group, or per-user. Contests are enforced as the source of problem visibility only while contest mode (or indv-contest mode) is on; outside it, contest start/stop windows are inert and access falls back to normal/group rules.
- **The instructor's operational model** (authoritative — this is the intended day-to-day usage, not just a technical description): the server lives in normal/group mode almost all the time; scores there are feedback, not authoritative — academic integrity in normal mode is handled socially, outside the grader. Contest mode is a short-lived "strict exam preset"; it is kept short both pedagogically (it blocks normal learning) and technically (several features assume small in-contest submission volumes, e.g. the O(N²) submission comparison and dataset rejudge).
- **Consequences, one line each** (see `User#problems_for_action`, `Problem.contests_problems_for_user`, `User#active_contests_range`, `MainController#prepare_list_information`):
  - In contest mode, students see ONLY the problems belonging to their currently-active, enrolled contests — the normal/group problem list is replaced wholesale, not merged in.
  - The main list scopes each student's displayed submissions/scores to `active_contests_range` — the union of their active contests' start/stop windows (adjusted for per-user offset/extra time) — so out-of-window submissions don't count toward the shown max score or count.
  - A user can lose the ability to view their OWN out-of-contest submissions while contest mode is on: `User#can_view_submission?` gates on the submission's problem being in `problems_for_action(:submit)` *before* the owner check, so a problem that falls outside the active-contest set becomes invisible even to its own submitter. This is intended, and symmetric across both code submissions and viva sessions.
- Viva-specific policy semantics (daily start limits, retakes, archived-session visibility, alert handling) build on top of this mode system but are documented separately — see `docs/superpowers/specs/2026-07-21-viva-context-policy-design.md` and `doc/Viva-Exam.md`.

### Key Domain Models

- **User** — has roles (admin, group_editor, reporter) via HABTM; scoped access to problems/contests
- **Problem** — programming problems with test cases, statements, attachments
- **Dataset** — test case sets for a problem (one is "live" at a time); contains Testcase records
- **Submission** — user code submissions; tracked through states: submitted → evaluating → done/error. `grader_comment` is a per-testcase result string (one character per testcase, in `Dataset#testcases.display_order`):
  - `P` — pass (full credit)
  - `T` — time limit exceeded
  - `x` — invalid operation (segmentation fault) or memory limit exceeded
  - `-` — wrong answer
  - `s` — partial credit on this testcase
  When diffing two grading runs (e.g. legacy vs migrated), only `T -> P` and `x -> P` transitions are usually benign — they reflect machine-speed or memory differences. All other transitions reflect real score changes worth investigating.
- **Contest** — time-bound competitions with users and problems
- **Group** — organizes problems and users (alternative to contests)
- **Job** — grading jobs (compile, evaluate, score) processed by external judge workers
- **Comment** — supports LLM-assisted hints with cost tracking
- **AuditLog** — polymorphic audit trail for changes to `GraderConfiguration`, `Contest`, `Problem`, `Dataset`, `Testcase`, `ContestProblem`, `ContestUser` (see "Audit Logging" below)

### JSON API (`/api/v1/`)

- Lives in `app/controllers/api/v1/`, routes under `namespace :api / :v1`
- **JWT auth** via `Authorization: Bearer <token>` (session auth is NOT used)
- **Must reuse existing model authorization** (`User#problems_for_action`, `User#can_submit_to_problem?`, `User#can_view_testcase?`, `User#can_view_submission?`, etc.) — never duplicate business logic in API controllers. The API must accept exactly what the web accepts — never less or more (decision 2026-08-22: the running web app is authoritative)
- **rswag** specs in `spec/requests/api/v1/` double as tests and Swagger docs
- After changing any API spec: **always run `rails rswag:specs:swaggerize`** to regenerate `swagger/v1/swagger.yaml`
- Swagger UI is served at `/api-docs`

### Controller Organization

- **MainController** — student-facing: problem list, submit code, view submissions
- **ProblemsController** — admin: manage problems, datasets, testcases
- **ContestsController** / **GroupsController** — manage contest/group membership
- **ReportController** — scoring reports, login analytics, plagiarism detection
- **UserAdminController** — user management, bulk operations
- **SubmissionsController** — view/rejudge submissions
- **Worker::* namespace** — API endpoints for judge worker communication
- **GradersController** — monitor/manage grader processes and job queues

### Authentication & Authorization

Session-based auth (`session[:user_id]`). Key controller methods:
- `current_user` — logged-in user
- `admin_authorization` — restricts to admin role
- `group_editor_authorization` — restricts to group editors

Submit authorization is ONE predicate, `User#can_submit_to_problem?` (admin ∨ `:submit` ∨ `:edit` — the `:edit` arm is the editor's test-submit right on draft/hidden problems in their own groups). It backs the web submit, the API create, viva start, the submit-form UI, and the model-layer validation (`Submission#must_have_valid_problem`, the last line of defense; trusted tooling bypasses with `save!(validate: false)`). Never hand-roll a submit check from scopes — add to or call the predicate. A disabled `groups_users` row grants NO role (member, reporter, or editor). Full design + role matrix: `doc/decisions.md` 2026-08-22, `docs/guide/authorization.html`.

### Background Processing

- **Solid Queue** handles Active Job (LLM assist, PDF generation)
- **Judge workers** are separate processes that poll `Job` records for grading tasks (configured in `config/worker.yml`)

### LLM Integration

- `app/services/llm/` — LLM service classes
- `config/llm.yml` — provider configuration
- Cost tracking integrated into scoring/reports

### Audit Logging

Change history for sensitive models is captured by the `Auditable` concern (`app/models/concerns/auditable.rb`) into the polymorphic `audit_logs` table.

**Audited models** and their tracked attributes are declared in-model via the `audited` DSL:

```ruby
include Auditable
audited only: %i[name stop ...]              # Contest / Problem / Dataset
audited only: %i[input sol ...], redact: %i[input sol]  # Testcase
audited                                       # GraderConfiguration — all attrs
```

- `only:` — whitelist of attributes. Omit to log every attribute (except id/timestamps).
- `redact:` — values for these fields are stored as `"[redacted]"` (use for large blobs like `Testcase#input`/`sol`). Changes are still detected and logged; just the content isn't stored.
- **Timing** — changes are *staged* in `after_save` and *written* in the `after_*_commit` callback: one row per record per transaction, first old / last new value per field, a field changed and changed back is dropped, a rollback discards the staging. So a `reload` or a second save between the save and the commit is safe (it was not before rev 2157 — `viva:import`'s post-check reload silently lost its rows), and `AuditLog.paused` suppresses a save whether or not an outer transaction is open. A record created and updated in one transaction gets a single `create` row showing the committed values.

**Actor tracking** — `Current.user` and `Current.ip` (from `app/models/current.rb`, an `ActiveSupport::CurrentAttributes`) are set by `ApplicationController#set_current_audit_context` on every request. Background jobs without a user context should set `Current.actor_note` manually (e.g. `"Job: DailyReset"`) so the row isn't anonymous.

**Consolidating bulk events** — when a single user intent touches many rows (mode switch, contest clone, bulk add/remove, reorder), suppress the per-row cascade and emit one semantic log:

```ruby
AuditLog.paused do                                    # auto-logging off inside block
  # cascade of row-level updates / saves
end
AuditLog.record!(auditable: @contest,                 # one manual row
                 action: 'bulk_add_users',            # free-form string
                 object_changes: { 'added_count' => [nil, n] })
```

`paused` restores the flag on exception via `ensure`; nothing raised means `record!` isn't called (no audit for failed actions). **Put any `save` that triggers autosave-cascading callbacks *inside* the `paused` block** — it's a common mistake to only pause the build phase and let autosave leak through. Example action strings already in use: `mode_change`, `clone`, `bulk_add_users*`, `bulk_add_problems*`, `bulk_enable/disable/remove_*`, `move_up`, `move_down`, `remove_user`, `remove_problem`.

**Bypass warning** — callbacks, and therefore audit rows, are **skipped** by:
- `update_all`, `update_columns`, raw SQL
- `delete` (vs `destroy`), `delete_all`
- **`has_many :through` collections** — `.delete`, `.clear`, and `=` replacement all default to a direct `DELETE` on the join table with no model instantiation. E.g. `@contest.users.delete(@user)` does **not** fire `ContestUser` destroy callbacks. To audit these, either explicitly record (`AuditLog.record!`) after the operation, operate on the join directly (`contests_users.where(user: @user).destroy_all`), or add `dependent: :destroy` to the through association.

**Admin UI** at `/audit_logs` (admin-only, linked from the Manage navbar dropdown). Per-record "Change history" buttons appear on the edit pages of `Contest`, `Problem`, `Dataset`, and `GraderConfiguration`. Two rollups are implemented in `AuditLogsController#apply_scope`:
- **Dataset** history includes its child `Testcase` rows.
- **Contest** history includes its child `ContestProblem` and `ContestUser` rows.

**Display customization** — `AuditLogsHelper` holds the display logic: `audit_target_label` produces human-friendly labels (e.g. `Contest: CP2026`, `ContestUser: CP2026 / alice`), and `audit_action_badge` maps each action string to a coloured Bootstrap badge with a Material icon. Add new branches there when introducing new semantic actions.

**Retention** — 6 months, enforced by a Solid Queue recurring task `audit_log_cleanup` in `config/recurring.yml` that calls `AuditLog.cleanup!` daily at 03:00 (production only). Ad-hoc clear: `AuditLog.delete_all` (safe; AuditLog does not audit itself).

### Multi-Database Setup

- Primary: `grader` — application data
- Queue: `grader_queue` — Solid Queue tables (migrations in `db/queue_migrate/`)

## Development Environment

- **File watcher (WSL2 critical):** `config/environments/development.rb` sets `config.file_watcher = ActiveSupport::EventedFileUpdateChecker`, backed by the `listen` gem. The Rails default (`ActiveSupport::FileUpdateChecker`) polls via `Dir.glob` on every request — on WSL2 that serializes concurrent requests on directory inode locks and made cascading turbo_frame requests (e.g. `/problems/:id/edit`) take ~2s each instead of ~80ms. If the cascade ever feels slow again, first check: did `listen` quietly fall back to polling? Look for "maximum number of watches reached" at boot. Current inotify limit: `cat /proc/sys/fs/inotify/max_user_watches` (default WSL2 was 8192 but this host has 524288). Raise with `sudo sysctl fs.inotify.max_user_watches=N`. listen docs: https://github.com/guard/listen. Rails' evented checker: https://api.rubyonrails.org/classes/ActiveSupport/EventedFileUpdateChecker.html.
- **In-page profiler:** `rack-mini-profiler` is in the `:development` gem group with `stackprof` for flame-graph support. Speed-badge appears top-right on every HTML page (configurable via `config/initializers/rack_mini_profiler.rb`). Per-request breakdown by clicking the badge; `?pp=flamegraph&flamegraph_mode=wall` for stack-sampling profile (wall-mode is essential for diagnosing I/O / lock contention — CPU mode misses it). Visit `?pp=help` for the full menu. Zero production impact (gem group isolation).

## Testing Notes

- **System tests + Turbo login:** the login form (`_login_box.html.haml`) uses `form_with`, which submits via Turbo. Capybara's `click_on 'Login'` returns once the click event fires, *before* Turbo's async fetch lands and replaces the page. A bare `visit some_path` immediately after will race the login and end up on the wrong page. In the local `login` helper for any new system test, sync after the click (e.g. `assert_current_path list_main_path, wait: 5`) before doing anything else.
- **Async turbo_stream submits race the DB read.** A form that responds with a turbo_stream (e.g. the `do_manage` "Apply to Selected" bulk actions, which append a Bootstrap toast) updates the DB *before* the response renders, but the submission is async — a test that does `record.reload` immediately after clicking submit reads stale data. Wait for a deterministic post-submit signal first: those bulk actions append a toast, so `assert_selector ".toast", wait: 10` before the DB assertion; a redirect-with-notice form, `assert_text "<notice>"`. This made 5 tests (Clusters 3 & 4 + the languages bulk-set) look like real regressions when the logic was fine.
- **Use an explicit `wait:` on assertions that follow an async submit.** The default Capybara wait (~2s) can time out under full-suite load, making a good test look "flaky." **Don't skip a flaky system test on a hunch** — verify the actual failure mechanism first (a controller-level test of the same logic, or a `page.evaluate_script` DOM diagnostic). Two tests were *wrongly skipped* on unverified diagnoses before the real causes (a load timeout; an async-submit race) were found.
- **Admin index DataTables load rows via AJAX on `window load`.** Tables like `user_admin/index` and problems-manage init the DataTable on a full page load and fetch rows via POST. After a create→redirect, reload the index and `assert_text …, wait: 10` for a row (a turbo redirect won't fire `window load`). The AJAX init reads the CSRF token — keep it null-safe (`querySelector('meta[name="csrf-token"]')?.getAttribute('content')` or the jQuery `.attr()` form); the unguarded `.getAttribute` throws when the meta tag is absent (forgery protection is off in test) and silently kills the whole table.
- **`fill_in` on a pre-filled field can append, not replace** (editing a Name that already reads "easy" → "easybeginner"). Pass `fill_options: { clear: :backspace }` when overwriting an existing value.

## Key Configuration

- `config/worker.yml` — judge worker settings
- `config/llm.yml` — LLM provider config
- `config/application.rb` — timezone is Asia/Bangkok; supports deployment under a subdir via `RAILS_RELATIVE_URL_ROOT`
- `GraderConfiguration` model — runtime settings stored in DB (exam mode, contest mode, etc.)

## Frontend & UI Conventions

- **Icons:** Use the custom `.mi` class (e.g., `<span class="mi">edit</span>`) to render Google Material Symbols. Do *not* use raw SVGs or standard `material-icons` classes, as `.mi` is deeply integrated and optimized via `my_custom.scss`.
- **Tooltips & JavaScript UI:** Any element requiring Bootstrap JS (like `data-bs-toggle="tooltip"`) **MUST** be placed inside a parent container that possesses the `data-controller="init-ui-component"` Stimulus attribute. This guarantees the tooltip perfectly survives Hotwire/Turbo Frame reloads.
- **Data attributes — always use flat keys**, never nested hashes. Write `data: { bs_toggle: 'tooltip', bs_title: 'Save' }`, not `data: { bs: { toggle: 'tooltip' }, bs_title: 'Save' }`. HAML's attribute hash flattens nested hashes with hyphens, so the nested form *appears* to work inside `%button{...}` / `%a{...}` — but Rails' tag helper (`link_to`, `form_with`, `button_to`, `content_tag`, …) JSON-encodes nested hash values instead, producing `data-bs='{"toggle":"tooltip"}'` and silently breaking every Bootstrap component that reads `data-bs-toggle`. Always flat keeps both paths working. Underscores in keys become hyphens (`bs_toggle` → `data-bs-toggle`).
- **Tooltips on non-tooltip toggles:** `data-bs-toggle` holds a single value, so a button that triggers an offcanvas/dropdown/modal can't also say `="tooltip"`. The `init-ui-component` controller specifically picks up `[data-bs-title][data-bs-toggle]:not([data-bs-toggle="tooltip"])` and wires a Bootstrap tooltip on it — so the recipe is: keep `data-bs-toggle="offcanvas"` (or whatever) and add `data-bs-title="…"` for the hover label.
- **Server-mutating clicks (Turbo Streams):** Any click that performs a server-side action (toggle, delete, bulk-action, rejudge, etc.) MUST use a `<form>`, never `link_to ..., data: {remote: true}`. The codebase disables Turbo's link-driving (`Turbo.session.drive = false` in `app/javascript/application.js`), so every mutating form must opt in explicitly with `form: {data: {turbo: true}}`. Two sub-patterns:
  - **Flavor A (default) — `button_to` directly.** Use for one-shot actions where the URL/params are statically known. Example: dropdown bulk actions in `contests/show.html.haml`; the Rejudge button in `submissions/show.html.haml`. Pattern: `button_to "Label", path, class: 'btn ...', form: {class: 'd-inline', data: {turbo: true}}`.
  - **Flavor B — hidden form + Stimulus controller.** Use only when many similar controls hit the same endpoint with different per-row params, or when the visible control isn't a `<button>` (e.g. a checkbox switch). One hidden `form_with` lives once on the page; visible controls have `data-action="<stim>#<method>"` and the Stimulus controller fills hidden fields and submits. Examples: per-problem switches on `problems/index.html.haml`, per-row do_user/do_problem actions on `contests/show.html.haml`.
  - **Confirmations** use `'turbo-confirm': '...'` on the form's `data` (replaces the legacy `data-confirm`).
  - **Response shape — toast feedback.** The standard response is `@toast = {title: '...', body: '...', type: :notice}` and `render 'turbo_toast'`. Rails falls back to the shared `app/views/application/turbo_toast.turbo_stream.haml`, which appends a Bootstrap toast to `#toast-area` via the `_toast` partial. Toast types: `:notice` (default), `:alert`, `:warning`. Avoid ad-hoc alert divs prepended to `#main-content` — that's the legacy `.js.haml` shape.
- **Select2 in repeated forms:** When rendering the same `select_tag` (or `f.select`) in a loop — e.g. one form per role / group / role-panel — pass an explicit unique `id:`. Without it, Rails auto-generates `id="<name>"` for every iteration, the duplicate DOM ids are invalid HTML, and Select2 silently fails to wrap the second select while the first still works.
- **Vertical Rhythm (Spacing):** When defining the structural gaps between major cards or column sections, strictly normalize on `.mb-4` (24px) to ensure perfect horizontal alignment and grid consistency across the Left and Right panes.
- **Stateless Dismissals:** For transient, short-lived UI states (like dismissing an "Updated" notification badge during a contest), use lightweight, cookie-based JavaScript rather than storing read-states in the primary `grader` database.
- **Admin Controls:** When creating buttons exposed only to administrators (e.g., manage, edit, delete), use the elevated, icon-based pill button pattern: `class="btn btn-sm bg-white shadow-sm border-0 text-secondary d-inline-flex align-items-center justify-content-center"`. This should be paired with a Material Symbol inside (`<span class="mi">icon_name</span>`) and an active Bootstrap tooltip pointing out the action (`data-bs-toggle="tooltip" title="..."`).
- **Offcanvas help triggers (exception to icon-only):** A button that opens a Bootstrap offcanvas help drawer should be **labeled**, e.g. `? Help`, not icon-only — even though it sits next to the icon-only Admin Controls. Operator buttons (Stats / Download / History) are invoked by users who already know what they do; help is the opposite — the people who need it most are the least likely to recognize a bare `?` icon. The visible label is the discoverability mechanism that makes the offcanvas pattern usable. Keep the elevated-pill class set, add `gap-1` for icon↔label spacing, and keep `data-bs-title="Help"` so the tooltip survives for icon-only viewports.
- **Help-pattern split (context-dependent):** Two help patterns coexist intentionally — **inline knowledge card** (`_xxx_help.html.haml` rendered in the right column) on index/overview pages where there's empty space anyway and discoverability matters most for new admins; **offcanvas drawer** on edit/detail pages where space is at a premium. Do not invent a third pattern. When adding help to a new view, pick the one that matches the page type. The drawer trigger follows the labeled-button rule above.
- **Admin DataTables:** Administrative data table definitions should natively implement `.table.table-hover.table-condense.align-middle` to dramatically improve vertical data density.
- **JSON-fed DataTables escape by default:** DataTables writes cell data with innerHTML, so a plain `{data: 'full_name'}` column renders markup carried in the JSON (user full names are self-set at registration; the login-failure report shows raw attempted logins — this was stored XSS, rev 2079). Every `columns` array of an AJAX/JSON-fed table MUST go through `cafe.dt.escape_columns_by_default([...])` (the `datatables--init` controller does it for every `configs.js` table); custom `render` functions MUST wrap free-text fields in `escapeHtml(...)`. A column that deliberately shows server-built HTML opts out with an explicit identity `render: (d) => d`. Never apply the helper to a DOM-sourced table — there the cell data *is* the server's HTML.
- **Three markdown renderers, pick by who wrote the text** (`ApplicationHelper`): `safe_markdown` *escapes* raw HTML and links only http(s)/ftp/mailto/relative URLs — for text a student or a model wrote (viva turns, viva grade feedback, AI-assist bodies, the editor preview); `sanitized_markdown` runs an HTML *allow-list* (`STAFF_HTML_TAGS` / `STAFF_HTML_ATTRIBUTES`: Rails' defaults plus `table`/`font`, `target`/`color`/`size`/`border`) — for text a group editor or TA wrote (announcements, hints, submission comments; production announcement bodies use those tags, so escaping would break them); bare `markdown` passes HTML through and is only for admin-authored content. `sanitized_html` is the same allow-list without the markdown pass. Plain text a student or a model wrote goes through `simple_format_escaped`, never bare `simple_format` — its sanitizer reads `vector<int>` as a tag and shows `vector` (the viva grade feedback and student messages did this until revs 2287–2288; `test/no_bare_simple_format_test.rb` now fails on any bare call in `app/views` or `app/helpers`). Never `.html_safe` a stored title or a compiler message — render titles as text and compiler output with `content_tag(:pre, …)`; the toast partial escapes its body, so a caller that builds HTML marks it safe itself (issue #50, rev 2220).
- **Table Action Columns (Progressive Condensation):** Standardize row-level table actions into a single, right-aligned compact column (`<td class="align-middle py-1 pr-2">`). We apply a strict **Progressive Condensation** rule:
  - **High Action Density (>2 UI controls per row):** Pack all controls, especially destructive actions like "Remove", securely inside a `more_horiz` dropdown menu to completely eliminate horizontal bloat and prevent accidental 1-click deletions.
  - **Low Action Density (1-2 controls):** Extract these controls as naked, **Icon-Only** buttons leveraging standard padding (`class="btn btn-outline-{color} border-0 py-1 px-2"`), entirely eschewing verbose text labels in favor of HTML `title` attributes. Provide a clean trailing edge using `<div class="d-flex gap-1 justify-content-end">`. Ensure Material Icons target the default 24px container (do not append `.md-18`).
