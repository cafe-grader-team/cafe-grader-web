# Viva exam + LLM refactor — handoff (last updated 2026-05-09)

Working notes for resuming on a different machine. Started 2026-05-07 with
the LLM refactor; updated through 2026-05-09 with the viva-feature work
that followed (PDF-in-message, polling-scroll fix, grader diagnostics,
admin re-run + archive, end-to-end smokes).

## Current state at a glance

| | Value |
|---|---|
| **master** bookmark | rev `1689` |
| **chula_cp** bookmark | rev `1687` |
| Working directory | should be on **chula_cp** when running the dev server / Solid Queue worker — `Llm::VivaTurnGenieAssist` etc. only exist on chula_cp; switching to master breaks autoload for the running worker |
| GitHub mirror | **4 commits unpushed** — `hg push` before machine switch |
| Smoke tests | A ✓ (setup validation blocks bad start), B ✓ (happy-path viva), **C pending** (abstract base graceful failure), **D pending** (comment-assist cost=10) |

## What works end-to-end now

- **Viva start** validates `Problem#viva_setup_errors` (requires a `# Rubric` section in the `llm_prompt` tag); refuses with a clear flash if missing.
- **Viva turn** delivers system-prompt + scenario + grounding + PDF in one consolidated user message; transcript turns alternate cleanly; markdown rendered via `safe_markdown` (HTML-filtered); scroll position preserved across polling refreshes.
- **Viva end** detects `[[VIVA_DONE]]`, transitions submission to `:evaluating`, runs `Llm::VivaGradeAssistJob`, the polling UI shows "Grading in progress…" until grade lands.
- **Grade landing** renders the grade card (`:done`) or the red error alert (`:grader_error`); editor Debug card shows raw response, request payload preview, per-turn responses.
- **Admin actions** on `/submissions/:id/viva`:
  - **Re-run grading** with optional model override (Genie roster: gemini-2.5-pro/flash/etc., Claude-Sonnet/Haiku, gpt-4o-mini).
  - **Archive viva** — soft-archive (sets `submissions.viva_archived_at`), preserves transcript/grade/cost, frees the slot for a fresh viva.
- **Solid Queue dashboard** (`/grader_processes/queues`) filterable by status; failed jobs show exception detail + backtrace.

## Today's history (2026-05-09 cleanup)

The 14-commit churn from 2026-05-08 was collapsed into 3 logical commits per
branch via `hg strip --keep` + re-commit. The new branch tips are:

```
chula_cp:                                   master:
  1687  scroll fix (innerHTML)                1689  scroll fix (innerHTML graft)
  1686  viva_archived + admin archive         1688  viva_archived + admin archive (graft)
  1684  doc handoff                           1685  doc handoff (graft)
       (← shared ancestor at 1683)
```

`.hg/strip-backup/` has the bundles for the original 14-commit version if
ever needed (you shouldn't).

## Remaining tasks (priority order)

### 1. **`hg push`** — 4 commits unpushed

```bash
hg push     # mirrors both master and chula_cp via hg-git
```

Do this before machine switch.

### 2. Smoke C — abstract base raises gracefully

Verifies the error-feedback chain when `viva_turn_service` is unset
(simulating master). Detailed steps:

1. Edit `config/llm.yml` — blank out `viva_turn_service:` (remove
   `Llm::VivaTurnGenieAssist`).
2. **Restart Solid Queue worker** (config is read at boot).
3. Verify abstract is picked: `bin/rails runner 'puts Llm::VivaTurnAssistJob.new.send(:service_class).inspect'` should print `Llm::VivaTurnAssist`.
4. **Archive the existing test_viva submission** (Admin card button) so Start Viva reappears on /main/list.
5. Click Start Viva on test_viva. Land on a new session.
6. Within ~3s, assistant turn placeholder flips to `:error` with content like `"LLM error: NotImplementedError: Llm::VivaTurnAssist must implement #execute_call …"`. Red error frame in the chat.
7. Open `/grader_processes/queues`, click Failed filter — the failed job appears with `NotImplementedError`, message, and expandable backtrace.
8. **Restore** `config/llm.yml`: set `viva_turn_service: Llm::VivaTurnGenieAssist`. Restart worker.

### 3. Smoke D — comment-assist score penalty

```bash
# Find an eligible non-viva problem with an llm_prompt tag
bin/rails runner '
problems_with_prompt = Problem.joins(:tags)
  .where(tags: {kind: :llm_prompt})
  .where.not(compilation_type: 2).distinct
puts "Eligible:"
problems_with_prompt.limit(5).each { |p| puts "  ##{p.id} #{p.name}" }
'
```

Pick one, find a submission on it, trigger an LLM hint via the UI
(button on `/submissions/:id`), then verify `cost=10` on the resulting
Comment.

### 4. Recover #922237 (or any in-flight viva)

`#922237` is in `:grader_error` from when gemini-2.5-flash returned prose
instead of JSON. Recovery options:

- **Add `# Rubric` section** to test_viva's `llm_prompt` tag (snippet in
  this doc earlier — let the grader actually have something to score
  against).
- **Re-run grading** with `gemini-2.5-pro` from the model picker. Pro is
  much stricter about JSON-only output. If it fails again, the new failure
  raw response will overwrite the old one in the Debug card.
- Or **Archive viva** to start completely fresh.

### 5. Update test_viva's `llm_prompt` to drop `{{...}}` literals

The current prompt has `{{TOPIC_NAME}}`, `{{MAX_TURNS}}`, `{{TARGET_BLOOM_LEVEL}}`,
etc. that the backend doesn't substitute — they appear verbatim to the model.
Prompt-author work, not code.

### 6. Optional / deferred (won't block normal use)

- **Stuck-turn watchdog** — periodic sweep marking long-`:processing`
  turns as `:error`.
- **Retry/discard buttons** on `/grader_processes/queues` for failed
  Solid Queue jobs.
- **Status-column badges** on the queues table.
- **Persist `llm_request_raw` on viva_grade** (currently the Debug card's
  request payload is reconstructed via `Llm::Request.preview`).
- **Drop the unused index** `index_submissions_on_viva_archived_at` —
  `user_id` index dominates the gate query, the new index doesn't help
  reads but slows writes.

## How to resume on a different machine

```bash
hg pull && hg update chula_cp           # working branch for running things
bin/rails db:migrate                    # in case schema changed (rev 1686 added viva_archived_at)
bundle install                          # in case Gemfile changed
bin/dev                                 # server + worker

# Read this doc + recent log:
hg log --limit 10 --template "{rev} [{bookmarks}]: {desc|firstline}\n"
```

**Don't run anything while on `master`** — chula_cp-only files
(`Llm::VivaTurnGenieAssist`, `GenieAssist`, `TokenManager`, etc.) won't
exist there and the worker will crash with `NameError: uninitialized
constant`. Only switch to master to make code changes; switch back
before running.

## Useful console snippets

```ruby
# Inspect a viva submission
sub = Submission.find(<id>)
sub.viva_turns.ordered.each { |t| puts "##{t.id} #{t.role}/#{t.status}: #{t.content.to_s[0,80]}" }
sub.viva_grade&.attributes&.slice("total_points", "narrative", "llm_response_raw")
sub.viva_archived?

# Preview the next grader request (what would be sent)
require "json"
puts JSON.pretty_generate(Llm::VivaGradeGenieAssist.preview(submission: sub))

# Preview the next viva-turn request
puts JSON.pretty_generate(Llm::VivaTurnGenieAssist.preview(submission: sub, turn: nil))

# Archive a viva manually (or via the Admin card UI)
sub.update!(viva_archived_at: Time.current)

# Retry a failed Solid Queue job
SolidQueue::FailedExecution.find(<id>).retry

# Find the latest failed grader job
SolidQueue::FailedExecution.joins(:job)
  .where("solid_queue_jobs.class_name LIKE ?", "Llm::VivaGrade%").last
```

## Key files

```
app/services/llm/
  request.rb              # abstract base — call template, rescue, pdf_attachment, preview
  comment_assist.rb       # comment-on-submission shape (master)
  viva_turn_assist.rb     # viva interview turn shape (master)
  viva_grade_assist.rb    # viva grading shape (master, KNOWN_MODELS = [])

  # chula_cp only:
  genie_assist.rb              # GenieAssist < CommentAssist
  viva_turn_genie_assist.rb    # < VivaTurnAssist (DEFAULT_MODEL = gemini-2.5-flash)
  viva_grade_genie_assist.rb   # < VivaGradeAssist (KNOWN_MODELS = 8 models)
  token_manager.rb              # Genie bearer-token cache

app/jobs/llm/
  request_job.rb          # abstract — retry policy, perform(submission, **kwargs)
  comment_assist_job.rb   # marker for comment-style jobs (master)
  viva_turn_assist_job.rb # configured via Rails.configuration.llm[:viva_turn_service]
  viva_grade_assist_job.rb

app/controllers/
  viva_sessions_controller.rb  # start / show / answer / refresh + load_viva_state
  submissions_controller.rb    # rejudge (model picker), archive_viva
  main_controller.rb           # /main/list — filters submissions on viva_archived_at IS NULL

app/views/viva_sessions/
  show.html.haml          # page shell + Viva Info / Admin / Debug cards
  _viva_session.html.haml # chat area; case branch on submission.status
  _turn.html.haml         # markdown for assistant via safe_markdown
  _answer_form.html.haml

app/javascript/controllers/
  viva_session_controller.js   # 3s polling via innerHTML swap (preserves scroll anchor)

app/presenters/llm/
  request_job_presenter.rb     # used by /grader_processes/queues + /report

app/models/
  submission.rb           # Submission#viva_archived? predicate
  problem.rb              # Problem#viva_setup_errors, viva_prompt_tags

config/
  llm.yml                       # llm_services anchor with viva_turn_service / viva_grade_service
  initializers/cafe_grader.rb   # loads llm.yml; LLM_NON_SERVICE_KEYS skip-list
  routes.rb                     # archive_viva on submission member

db/migrate/
  20260508120000_add_viva_archived_at_to_submissions.rb
```
