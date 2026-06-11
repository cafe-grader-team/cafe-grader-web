# API v1 write endpoints — implementation plan

Goal: add Create/Update/Delete to `/api/v1/` for **problems, datasets, testcases, users**,
reusing the web controllers' semantics and the model-layer authorization helpers
(per CLAUDE.md: never duplicate business logic in API controllers).

Status: **implemented 2026-06-11** (all phases). Kept as design rationale. Deviations from
the original plan, made during implementation:
- Statement PDF upload became `PUT /api/v1/problems/:id/statement` (dedicated multipart
  endpoint) instead of a multipart variant of PATCH — one content type per operation keeps
  the rswag/OpenAPI definitions clean.
- Dataset file upload likewise became `POST /api/v1/datasets/:id/files`; `PATCH /datasets/:id`
  is JSON-only.
- Testcase create/update accept `input`/`sol` as either file uploads or plain-text fields
  (top-level params, metadata under `testcase`).
- `GET /api/v1/users/:id` (show) added alongside index.
- Problem/testcase write lookups intentionally bypass the student `submit` scope
  (`set_problem_for_edit`): editors must reach unavailable problems; 404 for unknown ids,
  403 when found but not editable.

## Decisions

- **Authorization mirrors the web side exactly:**
  - problem create → editor role (`group_editor_authorization` equivalent: admin OR `groups_for_action(:edit).any?`)
  - problem/dataset/testcase member ops → `current_user.can_edit_problem?(problem)` (the API problems controller's existing `authorize_edit!`)
  - all user endpoints → `current_user.admin?` (mirrors `UserAdminController`)
- **Same JWT bearer auth; no new scheme.** Roles are re-read from DB on every request
  (`base_controller.rb`), so role revocation takes effect immediately.
- **Testcase content is ActiveStorage** (`inp_file`/`ans_file`), not the legacy `input`/`sol`
  text columns — mirror `ProblemImporter` (`app/engine/problem_importer.rb:98-104`),
  including the CRLF normalization (`gsub(/\r$/, '')`).
- **Role granting/revoking is deliberately NOT exposed** (web `modify_role` stays web-only).
  It is the privilege-escalation surface; revisit only with a stronger token story.

## Phase 0 — token hardening (DONE)

- `Api::V1::AuthController::TOKEN_TTL = 12.hours` (was 7 days). Bearer tokens have no
  server-side revocation, so TTL = exposure window of a leaked token.
- Note: tokens issued *before* this deploys remain valid up to 7 days (exp is baked in).
- Backlog (optional hardening): `token_version` column on users checked at decode, so
  outstanding tokens can be invalidated; dedicated signing key instead of
  `secret_key_base` so rotating one doesn't kill the other.

## Phase 1 — API base infrastructure (prerequisite for all writes)

All in `app/controllers/api/v1/base_controller.rb` unless noted.

1. **Audit actor context (critical).** `Current.user` / `Current.ip` are only set by
   `ApplicationController#set_current_audit_context`; the API base inherits
   `ActionController::API`, so today any API mutation of an audited model would write an
   **anonymous audit row**. Set both at the end of `authenticate_api_user!`
   (single choke point, can't be skipped by ordering).
2. **Disabled-user gate.** Web blocks disabled users per-request
   (`application_controller.rb:193`: `enabled? || admin?`); `User.authenticate` only checks
   `activated`, so the API currently issues tokens to disabled users and lets them read.
   Add the same gate after authentication, and refuse login outright for disabled non-admins.
3. **Role helpers**: `require_admin!` and `require_editor!` (admin or
   `groups_for_action(:edit).any?`), both rendering `{error: …}, status: :forbidden`.
4. **Login rate limit**: Rails 8 built-in `rate_limit to: 10, within: 1.minute, only: :login`
   on the auth controller (backed by Solid Cache). Currently brute-force is unthrottled.
5. **Login response**: add `expires_at` so clients know when to re-auth
   (requires touching `auth_spec.rb` schema + swaggerize).
6. **Error conventions** (document in swagger): 401 unauthenticated, 403 unauthorized,
   404 via `render_not_found`, 422 `{error: "Validation failed", details: [...]}`,
   409 for state-rule conflicts (e.g. deleting the live dataset).

## Phase 2 — Problems CUD (`app/controllers/api/v1/problems_controller.rb`)

| Verb | Path | Authz | Notes |
|---|---|---|---|
| POST | `/api/v1/problems` | editor | transactional create incl. default dataset + `live_dataset`, mirroring web `quick_create` (`problems_controller.rb:119-137`) — a dataset-less problem is invisible to manage views |
| PATCH | `/api/v1/problems/:id` | `can_edit_problem?` | same params as web `problem_params`; `permitted_language_ids: []` handled like web update (ids → names string); statement upload must be `application/pdf` (mirror web check) |
| DELETE | `/api/v1/problems/:id` | `can_edit_problem?` | `@problem.destroy` like web; verify submission FK behaviour during implementation |

JSON body params (from web `problem_params`): `name, full_name, available, date_added,
test_allowed, output_only, difficulty, submission_filename, compilation_type, view_testcase,
view_submission, markdown, description, url, tag_ids: [], group_ids: []`.
Statement PDF upload = multipart variant of PATCH.

Audit: automatic (Problem is `audited`) once Phase 1.1 lands.

## Phase 3 — Datasets (new `app/controllers/api/v1/datasets_controller.rb`)

| Verb | Path | Notes |
|---|---|---|
| GET | `/api/v1/problems/:id/datasets` | list with settings + testcase summary (clients need ids to drive the rest) |
| POST | `/api/v1/problems/:id/datasets` | default name via `Problem#get_next_dataset_name` when absent |
| PATCH | `/api/v1/datasets/:id` | JSON: `name, time_limit, memory_limit, score_type, evaluation_type, score_param, main_filename, initializer_filename`; multipart: `checker, managers[], data_files[], initializers[]` (attach like web `datasets_controller.rb:56-58`) |
| DELETE | `/api/v1/datasets/:id` | 409 if last dataset or live dataset (mirror web rules) |
| POST | `/api/v1/datasets/:id/set_live` | `problem.update(live_dataset:)`; auto-audited (`live_dataset_id` is in Problem's audited list) |
| DELETE | `/api/v1/datasets/:id/files/:attachment_id` | mirror web `file_delete` incl. `update_main_filename` re-save |

All authz: `require_editor!` + `can_edit_problem?(dataset.problem)`.

**Worker cache invalidation:** judge workers cache dataset files via `WorkerDataset`.
Fix the latent bug in `Dataset#invalidate_worker` (`app/models/dataset.rb:135` uses `@dataset`,
which is nil inside the model — should be `id`), then call it from every content-affecting
endpoint (file attach/delete, checker change), mirroring `datasets_controller.rb:62-64`.

## Phase 4 — Testcases (extend `app/controllers/api/v1/testcases_controller.rb`)

| Verb | Path | Notes |
|---|---|---|
| POST | `/api/v1/datasets/:id/testcases` | content as multipart files **or** JSON text (`input`, `sol`); metadata `num` (default: next), `weight, group, group_name, code_name`; attach `inp_file`/`ans_file` exactly like `ProblemImporter` |
| PATCH | `/api/v1/testcases/:id` | metadata update and/or content replacement |
| DELETE | `/api/v1/testcases/:id` | |
| POST | `/api/v1/problems/:id/testcases/import` | *(optional but recommended — the realistic bulk path)* zip via `ProblemImporter#import_dataset_from_dir` like web `import_testcases`; wrap in `AuditLog.paused` + one `AuditLog.record!(action: 'api_import_testcases')` per the bulk-consolidation rule |

Authz: `require_editor!` + `can_edit_problem?(testcase.dataset.problem)`.

**Worker cache:** invalidate on create/delete/content-replace (workers cache testcases too —
`WorkerDataset#testcases_status`). Note the web `testcase_delete` *doesn't* invalidate
(latent staleness bug) — fix it there too while at it. Metadata-only changes (weight/group)
need no invalidation (scoring reads the DB; `set_weight` precedent).

Audit: automatic; `input`/`sol` are already `redact:`-ed. Attachment-only changes don't
produce attribute diffs — acceptable, matches web behaviour.

## Phase 5 — Users (extend `app/controllers/api/v1/users_controller.rb`, all `require_admin!`)

| Verb | Path | Notes |
|---|---|---|
| GET | `/api/v1/users` | paginated, `q` filter on login/full_name (needed to drive CUD) |
| POST | `/api/v1/users` | web `user_params`: `login, password, password_confirmation, email, alias, full_name, remark, enabled, group_ids: []`; force `activated = true` like web create |
| PATCH | `/api/v1/users/:id` | same params |
| DELETE | `/api/v1/users/:id` | mirror web destroy |

Known gap (pre-existing): **User is not an audited model** — API user CUD won't leave audit
rows, same as the web UI today. Backlog candidate: `include Auditable` on User with
`redact: %i[hashed_password salt]`.

## Phase 6 — specs & docs (alongside each phase, not at the end)

- rswag specs in `spec/requests/api/v1/` per controller: happy path + 401/403/404/422
  (+409 for dataset guards). Reuse patterns from existing specs.
- `bundle exec rails rswag:specs:swaggerize` after every spec change; `bin/rails swagger:verify`.
- `bin/rails check` and `bundle exec brakeman` (new mass-assignment surfaces) before each commit.

## Suggested commit slicing

1. Phase 1 (infra + login hardening + `expires_at`) — independently shippable
2. Phase 2 problems
3. Phase 3 datasets (+ `invalidate_worker` fix)
4. Phase 4 testcases (+ web `testcase_delete` invalidation fix)
5. Phase 5 users
