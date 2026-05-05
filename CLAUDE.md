# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cafe-Grader is an online programming contest and assignment grading platform (used at Chulalongkorn University). Students submit code, which is automatically compiled and evaluated against test cases. Instructors manage problems, contests, groups, and view reports.

## Version Control

Local VCS is **Mercurial (hg)**, mirrored to **GitHub** via the **hg-git** extension. Use `hg` for all local operations (`hg status`, `hg commit`, `hg diff`, `hg push`). Issues and PRs live on GitHub — use the `gh` CLI for those (e.g., `gh issue close 51`).

## Tech Stack

- **Ruby 3.4.4, Rails 8.0.0** (with `load_defaults 7.0`)
- **MySQL** (primary DB: `grader`, queue DB: `grader_queue`)
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
bin/rails test                   # all tests
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
```

## Architecture

### Two Operating Modes

The system operates in either **contest mode** or **group mode** (configured via `GraderConfiguration`). This affects how problems are scoped and presented to users.

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
- **Must reuse existing model authorization** (`User#problems_for_action`, `User#can_view_testcase?`, `User#can_view_submission?`, etc.) — never duplicate business logic in API controllers
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

## Testing Notes

- **System tests + Turbo login:** the login form (`_login_box.html.haml`) uses `form_with`, which submits via Turbo. Capybara's `click_on 'Login'` returns once the click event fires, *before* Turbo's async fetch lands and replaces the page. A bare `visit some_path` immediately after will race the login and end up on the wrong page. In the local `login` helper for any new system test, sync after the click (e.g. `assert_current_path list_main_path, wait: 5`) before doing anything else.

## Key Configuration

- `config/worker.yml` — judge worker settings
- `config/llm.yml` — LLM provider config
- `config/application.rb` — timezone is Asia/Bangkok; supports deployment under a subdir via `RAILS_RELATIVE_URL_ROOT`
- `GraderConfiguration` model — runtime settings stored in DB (exam mode, contest mode, etc.)

## Frontend & UI Conventions

- **Icons:** Use the custom `.mi` class (e.g., `<span class="mi">edit</span>`) to render Google Material Symbols. Do *not* use raw SVGs or standard `material-icons` classes, as `.mi` is deeply integrated and optimized via `my_custom.scss`.
- **Tooltips & JavaScript UI:** Any element requiring Bootstrap JS (like `data-bs-toggle="tooltip"`) **MUST** be placed inside a parent container that possesses the `data-controller="init-ui-component"` Stimulus attribute. This guarantees the tooltip perfectly survives Hotwire/Turbo Frame reloads.
- **Server-mutating clicks (Turbo Streams):** Any click that performs a server-side action (toggle, delete, bulk-action, rejudge, etc.) MUST use a `<form>`, never `link_to ..., data: {remote: true}`. The codebase disables Turbo's link-driving (`Turbo.session.drive = false` in `app/javascript/application.js`), so every mutating form must opt in explicitly with `form: {data: {turbo: true}}`. Two sub-patterns:
  - **Flavor A (default) — `button_to` directly.** Use for one-shot actions where the URL/params are statically known. Example: dropdown bulk actions in `contests/show.html.haml`; the Rejudge button in `submissions/show.html.haml`. Pattern: `button_to "Label", path, class: 'btn ...', form: {class: 'd-inline', data: {turbo: true}}`.
  - **Flavor B — hidden form + Stimulus controller.** Use only when many similar controls hit the same endpoint with different per-row params, or when the visible control isn't a `<button>` (e.g. a checkbox switch). One hidden `form_with` lives once on the page; visible controls have `data-action="<stim>#<method>"` and the Stimulus controller fills hidden fields and submits. Examples: per-problem switches on `problems/index.html.haml`, per-row do_user/do_problem actions on `contests/show.html.haml`.
  - **Confirmations** use `'turbo-confirm': '...'` on the form's `data` (replaces the legacy `data-confirm`).
  - **Response shape — toast feedback.** The standard response is `@toast = {title: '...', body: '...', type: :notice}` and `render 'turbo_toast'`. Rails falls back to the shared `app/views/application/turbo_toast.turbo_stream.haml`, which appends a Bootstrap toast to `#toast-area` via the `_toast` partial. Toast types: `:notice` (default), `:alert`, `:warning`. Avoid ad-hoc alert divs prepended to `#main-content` — that's the legacy `.js.haml` shape.
- **Select2 in repeated forms:** When rendering the same `select_tag` (or `f.select`) in a loop — e.g. one form per role / group / role-panel — pass an explicit unique `id:`. Without it, Rails auto-generates `id="<name>"` for every iteration, the duplicate DOM ids are invalid HTML, and Select2 silently fails to wrap the second select while the first still works.
- **Vertical Rhythm (Spacing):** When defining the structural gaps between major cards or column sections, strictly normalize on `.mb-4` (24px) to ensure perfect horizontal alignment and grid consistency across the Left and Right panes.
- **Stateless Dismissals:** For transient, short-lived UI states (like dismissing an "Updated" notification badge during a contest), use lightweight, cookie-based JavaScript rather than storing read-states in the primary `grader` database.
- **Admin Controls:** When creating buttons exposed only to administrators (e.g., manage, edit, delete), use the elevated, icon-based pill button pattern: `class="btn btn-sm bg-white shadow-sm border-0 text-secondary d-inline-flex align-items-center justify-content-center"`. This should be paired with a Material Symbol inside (`<span class="mi">icon_name</span>`) and an active Bootstrap tooltip pointing out the action (`data-bs-toggle="tooltip" title="..."`).
- **Admin DataTables:** Administrative data table definitions should natively implement `.table.table-hover.table-condense.align-middle` to dramatically improve vertical data density.
- **Table Action Columns (Progressive Condensation):** Standardize row-level table actions into a single, right-aligned compact column (`<td class="align-middle py-1 pr-2">`). We apply a strict **Progressive Condensation** rule:
  - **High Action Density (>2 UI controls per row):** Pack all controls, especially destructive actions like "Remove", securely inside a `more_horiz` dropdown menu to completely eliminate horizontal bloat and prevent accidental 1-click deletions.
  - **Low Action Density (1-2 controls):** Extract these controls as naked, **Icon-Only** buttons leveraging standard padding (`class="btn btn-outline-{color} border-0 py-1 px-2"`), entirely eschewing verbose text labels in favor of HTML `title` attributes. Provide a clean trailing edge using `<div class="d-flex gap-1 justify-content-end">`. Ensure Material Icons target the default 24px container (do not append `.md-18`).
