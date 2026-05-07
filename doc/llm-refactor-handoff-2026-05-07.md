# LLM service refactor + viva error feedback — handoff (2026-05-07)

Working notes for resuming on a different machine. Captures the original
problem, the design decisions, what was committed, what's left, and a few
unresolved architectural questions worth re-reading before resuming.

## The original symptom

A viva job (`Llm::VivaTurnAssistJob`) failed when the user started a viva
on a `test_viva` problem. Two complaints:

1. **No user-visible feedback.** The placeholder `VivaTurn` stayed in
   `:processing` forever; the student saw an eternal "Interviewer is
   thinking…" spinner. Root cause: the abstract `Llm::VivaTurnAssist#execute_call`
   on `default` raises `NotImplementedError` (intentional — a deployment
   branch like `chula_cp` supplies the concrete subclass). `NotImplementedError`
   is a `ScriptError`, *not* a `StandardError`, so it escaped the service's
   narrow `rescue Faraday::Error / RuntimeError`. The placeholder was never
   updated.
2. **No admin diagnostic detail** at `/grader_processes/queues`. The page
   recorded "this job failed" but the presenter didn't surface the exception
   class, message, or backtrace.

## Design framing

Reading the parent class `Llm::SubmissionAssist` revealed it was mixing two
concerns:

- **Generic LLM-call orchestration**: `call` template, Faraday connection
  factory, abstract prepare/execute/handle interface.
- **Comment-on-submission domain logic**: `@record = @other_args[:comment]`
  invariant (raises ArgumentError if missing!), `@record.cost = 10`,
  `@record.llm_response = ...`, `@record.status = ...`, plus
  `parse_response` / `validate_response_body!` /
  `get_prompts_from_problem_tags` helpers.

`Llm::VivaTurnAssist` and `Llm::VivaGradeAssist` inherited from
`SubmissionAssist` for the orchestration but had to override `initialize`,
`handle_response`, and `handle_error` *entirely* to silence the comment
behavior. Net inherited surface that was actually used: the `call` template's
rescue and `self.connection(url)`. Net inherited surface that had to be
worked around: most of the rest. Classic "inherited for code reuse, not
is-a semantics" anti-pattern.

User decisions during planning:
- **Naming:** full rename `SubmissionAssist → Llm::Request` (accept chula_cp
  churn; do not preserve the misleading name).
- **Scope:** bundle the viva error-feedback fixes with the refactor (one
  cohesive change), not a separate plan.

## What was committed (master / `default` branch)

Three commits, in order:

1. **rev 1634** — `llm: introduce Llm::Request abstract hierarchy`. Adds
   `Llm::Request`, `Llm::CommentAssist`, `Llm::RequestJob`,
   `Llm::CommentAssistJob`. Unused on their own.
2. **rev 1635** — `llm: migrate viva to Llm::Request, rename presenter,
   expand queues dashboard`. Reparents viva services + jobs onto the new
   hierarchy; renames `SubmissionAssistJobPresenter` →
   `Llm::RequestJobPresenter` (now under `app/presenters/llm/`); deletes the
   old `submission_assist*` files; updates the two presenter callers
   (graders, report) and `report_controller`'s class-hierarchy filter
   (`<(Llm::RequestJob)`). **Also bundles the queue-dashboard improvements
   that were uncommitted in working dir from the same session**: status
   filter (All/Pending/Failed/Finished) backed by SolidQueue's own scopes,
   and per-row failure detail in the Detail column (exception class +
   message + expandable backtrace, reading `job.failed_execution.error`).
3. **rev 1636** — `llm: tighten viva error handling on top of new
   Llm::Request contract`. `VivaTurnAssist#handle_error` and
   `VivaGradeAssist#handle_error` switch from `update` to `update!` so a
   failure in the error path itself surfaces. `VivaGradeAssist#handle_response`
   stops swallowing `JSON::ParserError` and instead raises
   `Llm::Request::ResponseError`, letting the orchestration mark the
   submission `:grader_error` AND record a `FailedExecution` for admin view.

## The new error-handling contract (validated by Plan agent during planning)

`Llm::Request#call`:

```ruby
RETRYABLE = [
  Faraday::TimeoutError,
  Faraday::ConnectionFailed,
  ActiveRecord::Deadlocked,
  ActiveRecord::ConnectionTimeoutError
].freeze

def call
  data = prepare_data
  response = execute_call(data)
  handle_response(response)
rescue *RETRYABLE
  raise   # let the job retry; do NOT mark record :error (would flicker)
rescue StandardError, NotImplementedError => e
  @error = format_error(e)
  begin
    handle_error
  rescue => he
    Rails.logger.error("handle_error failed for #{self.class}: #{he.class}: #{he.message}")
  end
  raise   # bubble so Solid Queue records FailedExecution
end
```

Key points:
- `NotImplementedError` listed explicitly. Don't broaden to `ScriptError`
  (would over-catch `LoadError`/`SyntaxError`).
- `handle_error` defensively wrapped: a failure during error-marking
  (DB blip, validation) is logged but doesn't mask the original exception.
- `Llm::Request::ResponseError < StandardError` for deterministic upstream
  problems (bad JSON, wrong shape). Never listed in `retry_on`.
- Bare `raise` re-raises the original exception class; `retry_on Faraday::TimeoutError`
  etc. on the job match by `is_a?` and trigger retries correctly.

`Llm::RequestJob`:

```ruby
retry_on Faraday::TimeoutError,                wait: :polynomially_longer, attempts: 3
retry_on Faraday::ConnectionFailed,            wait: 5.seconds,  attempts: 3
retry_on ActiveRecord::Deadlocked,             wait: 5.seconds,  attempts: 3
retry_on ActiveRecord::ConnectionTimeoutError, wait: 10.seconds, attempts: 3
discard_on ActiveJob::DeserializationError    # placeholder gone — nothing to mark

def perform(*args, **kwargs)
  Rails.logger.info "Starting #{service_class.name}"
  service_class.call(*args, **kwargs)
rescue => e
  Rails.logger.error "Service #{service_class.name} failed: #{e.class}: #{e.message}"
  raise
end
```

Deliberately NOT using `discard_on` for `NotImplementedError` —
discard would silently drop the job (no `FailedExecution` row, no admin
visibility). We want admins to see misconfigured-deployment failures.

## What's left

### chula_cp follow-up commit (4 mechanical edits)

After merging `default` into `chula_cp`:

| File | Change |
|---|---|
| `app/services/llm/genie_assist.rb` | `class GenieAssist < SubmissionAssist` → `class GenieAssist < Llm::CommentAssist` |
| `app/services/llm/viva_turn_genie_assist.rb` | `SubmissionAssist.connection(genie[:host])` → `Llm::Request.connection(genie[:host])` |
| `app/services/llm/viva_grade_genie_assist.rb` | Same as `viva_turn_genie_assist.rb` |
| `app/jobs/llm/genie_assist_job.rb` | `class GenieAssistJob < SubmissionAssistJob` → `class GenieAssistJob < Llm::CommentAssistJob` |

`Llm::TokenManager` is independent; no change.

### Verification done so far (master)

- Boot smoke (autoloading + ancestry):
  ```
  Llm::Request.ancestors            # [Llm::Request, ...]
  Llm::CommentAssist.superclass     # Llm::Request
  Llm::VivaTurnAssist.superclass    # Llm::Request
  Llm::VivaGradeAssist.superclass   # Llm::Request
  Llm::CommentAssistJob.superclass  # Llm::RequestJob
  Llm::VivaTurnAssistJob.superclass # Llm::RequestJob
  Llm::VivaGradeAssistJob.superclass # Llm::RequestJob
  ```
- `bin/rails test test/services/llm/` — 11 tests, 42 assertions, 0 failures.
- `bundle exec rubocop app/services/llm app/jobs/llm app/presenters` — 9 files, 0 offenses.
- `grep "SubmissionAssist" app/ config/` — 0 references on master.

### Verification still needed

End-to-end UI checks (require an actual viva to be started):

1. **Master smoke (expected to fail visibly):** with `viva_turn_service:`
   blank in `config/llm.yml`, start a viva on a `test_viva` problem.
   Expected: placeholder `VivaTurn` flips to `:error` within ~3s with content
   `"LLM error: NotImplementedError: Llm::VivaTurnAssist must implement #execute_call …"`.
   Student UI shows red error frame, no eternal spinner.
   `/grader_processes/queues` (filter "Failed") shows the job with full
   exception detail (class, message, expandable backtrace).
2. **Retry no-flicker (chula_cp only, after follow-up):** stub
   `execute_call` to raise `Faraday::TimeoutError` once then succeed on
   retry. Expected: turn never flips to `:error` — stays `:processing`,
   then `:ok` on success. Solid Queue retry counter increments.
3. **Comment flow (chula_cp only, after follow-up):** submit a
   comment-assist request on a problem. Expected: assistant comment fills
   in normally; on error, Comment record gets `status: 'error'` with the
   formatted error body — same as before the refactor.

## Loose ends + open questions worth revisiting

Not blockers, but flagged during planning:

1. **`queues_query` still passes `nil` submission to the presenter**
   (`graders_controller.rb`), so user/problem cells in the queues table
   stay blank. Pre-existing gap unrelated to the refactor; could be fixed
   by mirroring the `report_controller` GID-resolution pattern.
2. **Status-column rendering is plain text.** Bootstrap-badge variants
   (red for failed, blue for running, etc.) are a small JS column-renderer
   change in `app/javascript/controllers/datatables/columns.js`.
3. **`get_prompts_from_problem_tags`** lives on `Llm::CommentAssist` now,
   but `Llm::VivaTurnAssist` already calls `@problem.viva_prompt_tags`
   directly. If both ever want the same helper, push it onto `Problem`
   itself; don't move it back up to `Llm::Request` (it's domain-specific).
4. **`comments_controller.rb:181`** dynamically resolves the assist job
   class from `Rails.configuration.llm[:provider][model_name]`. On master
   this never resolves to anything (no master-side concrete `CommentAssist`
   subclass). If/when a master-side concrete is added, that controller
   may need to be looked at again.
5. **`Llm::CommentAssistJob` is currently empty** (just inherits from
   `RequestJob` and re-raises the abstract `service_class` hook). It
   exists so chula_cp's `GenieAssistJob` can express "this is a
   comment-style job" in its parent class. If you're tempted to add
   behavior to it that applies to *every* LLM job, push it up to
   `Llm::RequestJob` instead.

## Earlier work in the same session (already committed before the refactor)

Pre-context for resuming reading:

- **rev 1631 / earlier:** schema.rb rebuilt from migrations to detect
  drift; net diff was real (text-column sizes, charsets on join tables,
  `started_at` type, NOT NULL on timestamps, removed stale
  `score_submissions`/`score_users` tables, renamed grader-process index).
  See `db/migrate/20260506220000_reconcile_schema_drift.rb` and the
  matching reconciliation. The Auditable concern was patched to no-op
  when `audit_logs` doesn't exist yet (early-migration safety).
- **Quick Create on `/problems`:** `ProblemsController#quick_create` was
  changed to redirect to index on success (uses the existing flash-notice
  flow) instead of an inline turbo_toast that depended on a `datatable:reload`
  event the page never wired up. No design refactor of that page (it's
  server-rendered, not AJAX-loaded like contests) — option C in the
  earlier critique was deferred.
