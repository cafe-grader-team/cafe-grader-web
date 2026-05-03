# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cafe-Grader is an online programming contest and assignment grading platform (used at Chulalongkorn University). Students submit code, which is automatically compiled and evaluated against test cases. Instructors manage problems, contests, groups, and view reports.

## Tech Stack

- **Ruby 3.4.4, Rails 8.0.0** (with `load_defaults 7.0`)
- **MySQL** (primary DB: `grader`, queue DB: `grader_queue`)
- **Propshaft** asset pipeline, **ImportMap** for JS, **cssbundling-rails** with Sass for CSS
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
yarn build:css --watch           # Sass compilation
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

### Multi-Database Setup

- Primary: `grader` — application data
- Queue: `grader_queue` — Solid Queue tables (migrations in `db/queue_migrate/`)

## Key Configuration

- `config/worker.yml` — judge worker settings
- `config/llm.yml` — LLM provider config
- `config/application.rb` — timezone is Asia/Bangkok; supports deployment under a subdir via `RAILS_RELATIVE_URL_ROOT`
- `GraderConfiguration` model — runtime settings stored in DB (exam mode, contest mode, etc.)

## Frontend & UI Conventions

- **Icons:** Use the custom `.mi` class (e.g., `<span class="mi">edit</span>`) to render Google Material Symbols. Do *not* use raw SVGs or standard `material-icons` classes, as `.mi` is deeply integrated and optimized via `my_custom.scss`.
- **Tooltips & JavaScript UI:** Any element requiring Bootstrap JS (like `data-bs-toggle="tooltip"`) **MUST** be placed inside a parent container that possesses the `data-controller="init-ui-component"` Stimulus attribute. This guarantees the tooltip perfectly survives Hotwire/Turbo Frame reloads.
- **Vertical Rhythm (Spacing):** When defining the structural gaps between major cards or column sections, strictly normalize on `.mb-4` (24px) to ensure perfect horizontal alignment and grid consistency across the Left and Right panes.
- **Stateless Dismissals:** For transient, short-lived UI states (like dismissing an "Updated" notification badge during a contest), use lightweight, cookie-based JavaScript rather than storing read-states in the primary `grader` database.
- **Admin Controls:** When creating buttons exposed only to administrators (e.g., manage, edit, delete), use the elevated, icon-based pill button pattern: `class="btn btn-sm bg-white shadow-sm border-0 text-secondary d-inline-flex align-items-center justify-content-center"`. This should be paired with a Material Symbol inside (`<span class="mi">icon_name</span>`) and an active Bootstrap tooltip pointing out the action (`data-bs-toggle="tooltip" title="..."`).
- **Admin DataTables:** Administrative data table definitions should natively implement `.table.table-hover.table-condense.align-middle` to dramatically improve vertical data density.
- **Table Action Columns (Progressive Condensation):** Standardize row-level table actions into a single, right-aligned compact column (`<td class="align-middle py-1 pr-2">`). We apply a strict **Progressive Condensation** rule:
  - **High Action Density (>2 UI controls per row):** Pack all controls, especially destructive actions like "Remove", securely inside a `more_horiz` dropdown menu to completely eliminate horizontal bloat and prevent accidental 1-click deletions.
  - **Low Action Density (1-2 controls):** Extract these controls as naked, **Icon-Only** buttons leveraging standard padding (`class="btn btn-outline-{color} border-0 py-1 px-2"`), entirely eschewing verbose text labels in favor of HTML `title` attributes. Provide a clean trailing edge using `<div class="d-flex gap-1 justify-content-end">`. Ensure Material Icons target the default 24px container (do not append `.md-18`).
