# Migrating from v1.x to v4.x

> **TL;DR.** v4.x is a ~6.5-year, multi-framework jump from `v1.0.0` (Rails 4.2 + Bootstrap 3, what's been on `master` since October 2019) to current (Rails 8 + Hotwire + Solid Queue + JSON API). Plan a maintenance window, take a full DB backup, expect to update Ruby + Rails + several config files by hand, and run two sets of migrations (primary DB + queue DB). If anything goes wrong, you can roll back to the `v1.0.0` tag without touching your database — assuming you took the backup.

---

## About the version numbering

This release introduces a retroactive version scheme on a project that was previously unversioned in git tags:

| Tag         | Era                                                              | Roughly what's in it                                              |
|-------------|------------------------------------------------------------------|-------------------------------------------------------------------|
| `v1.0.0`    | What `master` has been since 2019                                | Rails 4.2 + Bootstrap 3 + Sprockets + jQuery                      |
| `v2.0.0`    | Rails 5.2 era (~late 2019 – early 2022, retroactively tagged)    | Rails 5.2 + Bootstrap 3 + Sprockets                               |
| `v3.0.0`    | Hotwire-modernization era (~2023, retroactively tagged)          | Rails 7 + importmap + Bootstrap 5 + Turbo + Stimulus + new judge  |
| `v4.0.0+`   | Current era (2025 onwards)                                       | Rails 8 + Solid Queue + LLM features + JSON API + audit logging   |

**Most users will be on `v1.0.0`** because that's what the GitHub `master` branch has pointed at for years. If your last `git pull` predates the v1.0.0 tag being announced, that's still the era you're on. The `v2` and `v3` tags exist as historical anchors — you can check them out if you want a stepping-stone upgrade, but the rest of this guide assumes a direct `v1.0.0 → v4.x` jump.

---

## Before you start

1. **Take a full database backup of `grader`.** This guide assumes you can restore. (No Redis / Sidekiq backup needed — v1 has no third-party queue or cache; everything was filesystem / DB / Action Cable defaults.)
2. **Freeze new submissions** during the upgrade. Either disable login at the load balancer or set `GraderConfiguration` to a maintenance state before stopping the app.
3. **Drain the judge workers.** Let any in-flight `Job` rows finish, or accept that they will be re-queued.
4. **Check your Ruby manager.** v4 requires **Ruby 3.4.4**. v1 typically ran on **Ruby 2.5 – 2.7**.
5. **Check disk and DB user permissions.** v4 creates a second database (`grader_queue`).

If you cannot meet any of these prerequisites, **stay on v1** for now — see "Staying on v1 long-term" below.

---

## Compatibility matrix

The "was (v1.0.0)" column reflects what's actually been on `master` since 2019. The "now (v4.x)" column is the current state.

| Component         | Was (v1.0.0)                            | Now (v4.x)                                        | Notes                                                        |
| ----------------- | --------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------ |
| Ruby              | 2.5 – 2.7                               | **3.4.4**                                         | Hard requirement.                                            |
| Rails             | **4.2**                                 | **8.0** (`load_defaults 7.0`)                     | Three major versions in one jump.                            |
| Asset pipeline    | Sprockets only                          | **Propshaft + ImportMap + dartsass-rails**        | Node.js no longer required for the web app. No Webpacker step in between. |
| Background jobs   | None (no Active Job backend)            | **Solid Queue** (DB-backed)                       | First Active Job backend in project history; LLM/PDF jobs depend on it. |
| Cache             | File store (Rails default)              | **Solid Cache**                                   | DB-backed.                                                   |
| Action Cable      | Not used                                | **Solid Cable**                                   | DB-backed.                                                   |
| HTTP server       | Puma                                    | Puma                                              | (Thruster is bundled but optional; not used in the maintainer's deployment.) |
| JS framework      | jQuery + ad-hoc                         | **Hotwire (Turbo + Stimulus)** + jQuery (legacy)  | jQuery still present for legacy paths.                       |
| CSS framework     | **Bootstrap 3** (`bootstrap-sass 3.4.1`)| **Bootstrap 5** (`bootstrap ~> 5.3`)              | Direct jump — Bootstrap 4 was never adopted. Class-name churn is large. |
| Templates         | ERB / HAML mix                          | **HAML** (predominantly)                          | Most views were converted.                                   |
| API               | None                                    | **JSON API at `/api/v1/`** (JWT)                  | Swagger UI at `/api-docs`.                                   |
| Audit logging     | None                                    | **`audit_logs` table** + `Auditable` concern      | New schema.                                                  |

> **TODO (maintainer):** sanity-check exact Ruby range you remember v1.x deployments running on; expand if needed.

---

## Step-by-step upgrade

### 1. Snapshot

```bash
mysqldump -u root grader > grader-pre-v4.sql
```

### 2. Pull v4

```bash
git fetch origin
git checkout v4.3.2          # or whatever the current v4 release tag is
```

### 3. Install Ruby 3.4.4 and gems

```bash
rbenv install 3.4.4              # or asdf / chruby / mise equivalent
bundle install
```

### 4. Create the queue database

v4 uses a second MySQL database for Solid Queue tables.

```sql
CREATE DATABASE grader_queue CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL ON grader_queue.* TO 'grader'@'localhost';
```

Then update `config/database.yml` to define the `queue` connection (template provided in `config/database.yml.example`).

### 5. Run migrations — both databases

```bash
bin/rails db:migrate                # primary
bin/rails db:migrate:queue          # queue DB (Solid Queue tables)
```

There are **many** primary migrations spanning 6.5 years of evolution. They are additive against your existing data — no destructive schema changes — but the run is long; expect minutes on a populated DB.

### 6. Update config files

The following files require attention. Diff against your v1 versions:

- `config/database.yml` — add the `queue:` connection.
- `config/cable.yml` — switch adapter to `solid_cable`.
- `config/cache.yml` — switch to `solid_cache`.
- `config/queue.yml` — new file, defines Solid Queue worker pools.
- `config/recurring.yml` — new file, includes the daily `audit_log_cleanup` task.
- `config/worker.yml` — judge-worker config; format may have changed; verify paths.
- `config/llm.yml` — **new**; required only if you enable LLM features. Otherwise leave the providers list empty.
- `config/importmap.rb` — **new**; manages JS dependencies. There is no `app/javascript/packs` — Webpacker was never used.
- `Procfile.dev` — **new**; coordinates web + CSS watcher + queue worker.
- `.env` / credentials — JWT signing secret is required for the API; see `config/initializers/api_auth.rb`.

> **TODO (maintainer):** confirm exact filenames and add a `config/.example` for each new one.

### 7. Asset compilation

Sprockets is gone. Replaced by Propshaft + dartsass-rails + importmap-rails:

- Plain JS modules → live under `app/javascript/` and are pinned in `config/importmap.rb`.
- npm packages → pin via `bin/importmap pin <pkg>`.
- SCSS → handled by `dartsass-rails`; entry point is `app/assets/stylesheets/application.scss`.

```bash
bin/rails assets:precompile      # production (also compiles CSS via dartsass-rails)
bin/rails dartsass:watch         # dev — auto-rebuild CSS on .scss changes
```

In dev, `bin/dev` (foreman + `Procfile.dev`) starts the dartsass watcher alongside the web server and queue worker, so you usually don't invoke it directly.

### 8. Configure the Solid Queue worker

There is no Sidekiq/Redis to retire — v1 had no third-party queue. You're adding one.

```bash
bin/rails solid_queue:start      # dev (also started by bin/dev via Procfile.dev)
# production: see deploy/solid_queue.service.example
```

### 9. First boot smoke test

```bash
RAILS_ENV=production bin/rails server
```

Then verify, in this order:

1. Login as an admin.
2. `/grader/configuration` — confirm `GraderConfiguration` rows loaded; toggle exam mode off if it migrated on by accident.
3. `/audit_logs` — confirm new audit page renders.
4. Submit a problem with one user — confirm a Job is created and a Solid Queue worker picks it up (for any Active-Job-driven follow-on like LLM hint or PDF generation).
5. `/api-docs` — confirm Swagger UI loads.

---

## Breaking changes you should explicitly review

### Authentication and sessions
- Session-based auth is unchanged for the web UI.
- The new `/api/v1/` namespace **does not** accept session cookies. Issue a JWT via the login endpoint and pass `Authorization: Bearer <token>`.
- If you previously hand-rolled an API on top of session auth, those endpoints are gone. Port to `/api/v1/`.

### `GraderConfiguration` defaults
- Several keys were renamed or added across 6.5 years of changes; on first boot the app will log warnings for unknown keys from your v1 config.
- New keys (exam mode, LLM gating, audit retention) default to safe/off.

### Submission grading-comment string
- The per-testcase result characters are unchanged: `P`, `T`, `x`, `-`, `s`.
- Diffing v1 vs v4 grading runs of the same submission: **only `T → P` and `x → P` transitions** should be considered benign (machine speed / memory variance). Any other transition reflects a real score change worth investigating — the judge engine was rewritten in 2023 (`app/engine/`) and small evaluation differences exist.

### Judge engine internals
- The Rails-side engine that processes a `Job` was rewritten and now lives under `app/engine/`. The DB-table-polling architecture is unchanged — judge workers still poll the `Job` table — but if you have external scripts that imported old engine modules by path, they'll need re-pointing.

### Audit logging
- New `audit_logs` table is populated automatically going forward; **historical changes are not backfilled.**
- Default retention is 6 months, enforced by the `audit_log_cleanup` recurring task. Adjust in `config/recurring.yml` if you need longer.

### Front-end conventions
- Bootstrap 3 → Bootstrap 5 means substantial class-name churn in any custom views you maintain.
- Custom `.mi` CSS class for Material Symbols replaces any prior icon usage.
- Tooltips and other Bootstrap-JS components must live inside an element with `data-controller="init-ui-component"` to survive Turbo Frame reloads.

---

## Rolling back

If the upgrade fails:

```bash
git checkout v1.0.0
mysql -u root grader < grader-pre-v4.sql
# restart services
```

The v4 migrations are additive — keeping the new columns/tables in your DB will not break v1 — but restoring the snapshot is the cleanest path.

---

## Staying on v1 long-term

The `v1.0.0` tag is the frozen pre-cutover snapshot — it points at the same commit the GitHub `master` branch has had since October 2019. Expectations:

- **No** new features.
- **No** guaranteed security backports. If you find a critical issue, please open one anyway — the maintainer may patch it, but cannot commit to a timeline.
- Pinning to the tag is recommended over tracking any legacy branch.

If you need long-term support beyond best-effort, please open an issue describing your environment so we can gauge demand.

---

## Stepping-stone upgrades (optional)

If a single `v1.0.0 → v4.x` jump is too much for your environment, the retroactive `v2.0.0` and `v3.0.0` tags exist as intermediate stops:

- **v1 → v2** = Rails 4.2 → 5.2, Bootstrap 3 stays, no new infra.
- **v2 → v3** = Rails 5.2 → 7, Bootstrap 3 → 5, Sprockets → importmap, jQuery → Hotwire, judge engine rewrite.
- **v3 → v4** = Rails 7 → 8, Solid Queue arrives, LLM + JSON API + audit logging added.

Most users won't need this — it's only worth doing if you've heavily customized internals and want to bisect breakage. The `v1 → v4` matrix above is the supported path.

---

## Getting help

- Open an issue: <https://github.com/cafe-grader-team/cafe-grader-web/issues>
- Tag issues with `v1-to-v4-migration` so they're easy to triage.
- Include: Ruby version, Rails version (pre-upgrade — almost certainly 4.2), MySQL version, deployment style (Docker / bare metal / Capistrano / etc.), and the exact step where you got stuck.

---

## Maintainer checklist (delete before shipping)

- [ ] Confirm exact Ruby range typical of v1.x deployments (2.5–2.7 is a guess).
- [ ] Confirm exact list of new/renamed config files since v1 and provide `.example` versions.
- [ ] List `GraderConfiguration` keys that were renamed or removed since v1.
- [ ] Add `deploy/solid_queue.service.example` (or equivalent) referenced above.
- [ ] Verify the four retroactive tags point at the agreed hg revs and have been pushed to `cafe-grader-team/cafe-grader-web`:
  - `v1.0.0` → rev 777
  - `v2.0.0` → rev 814
  - `v3.0.0` → rev 901
  - `v4.0.0` → rev 1325
  - `v4.3.2` → rev 1564 (existing point release)
- [ ] After a few more commits past current HEAD, cut a fresh **`v4.4.0`** as the cutover release tag.
