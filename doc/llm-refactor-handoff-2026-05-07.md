# Viva exam + LLM refactor — handoff (last updated 2026-05-08)

Working notes for resuming on a different machine. Written initially after the
LLM refactor on 2026-05-07; updated on 2026-05-08 with the wave of viva-feature
work that followed. Captures current state, what's done, what's left, and the
unresolved issues with the in-flight test submission.

## Current state at a glance

| | Value |
|---|---|
| **master** bookmark | rev `1682` |
| **chula_cp** bookmark | rev `1683` |
| Working directory | should be on **chula_cp** when running the dev server / Solid Queue worker — `Llm::VivaTurnGenieAssist` etc. only exist on chula_cp, and switching to master breaks autoloading for the running worker |
| GitHub mirror | **all unpushed** since the original commits — neither bookmark has been pushed since the work started |
| Test viva submission | `#922237` (problem `test_viva`, user `nnattee`) — currently in `:grader_error`; needs the user's prompt to grow a `# Rubric` section and probably to be re-run with `gemini-2.5-pro` to produce valid JSON |

## The original symptom (recap)

A viva job failed when the user started a viva on a `test_viva` problem.
Two complaints:

1. **No user-visible feedback.** The placeholder VivaTurn stayed in `:processing`
   forever; student saw an eternal "Interviewer is thinking…" spinner.
2. **No admin diagnostic detail** at `/grader_processes/queues`. The page
   recorded "this job failed" but couldn't surface the exception.

The first cause was a too-narrow service-level `rescue Faraday::Error /
RuntimeError` that let `NotImplementedError` (from the abstract base) escape.
The second was a thin presenter that never read `SolidQueue::FailedExecution`.

## What's been done

### Phase 1 — Original refactor + admin diagnostics (2026-05-07)

These commits laid the groundwork. Every commit body has a thorough
explanation of the why; `hg log -r N --template "{desc}\n"` to read.

- **revs 1634–1637** — Llm::Request abstract hierarchy. Split the legacy
  `Llm::SubmissionAssist` into `Llm::Request` (orchestration) +
  `Llm::CommentAssist` (comment-on-submission shape) + matching jobs. New
  error-handling contract: split rescue between RETRYABLE (re-raise without
  touching record) vs everything else (mark record then re-raise so Solid
  Queue records the failure).
- **rev 1638** — chula_cp mechanical reparenting (GenieAssist onto
  CommentAssist, three connection() call updates, GenieAssistJob onto
  CommentAssistJob).
- **revs 1640–1643** — DRY lift: comment-assembly methods (build_messages,
  pdf_attachment, etc.) lifted from chula_cp's GenieAssist up to
  CommentAssist. GenieAssist shrunk from 219 → 71 lines. Adding a second
  comment-style provider is now ~30–40 lines.
- **rev 1666 (E+F equivalent for queues page)** — `/grader_processes/queues`
  got a status filter (All/Pending/Failed/Finished) and per-row
  failure-detail rendering (exception class + message + expandable
  backtrace).

### Phase 2 — Viva feature gap-fixing (2026-05-08)

| revs | What |
|---|---|
| 1644–1645 | **Perform-signature regression fix** — `RequestJob#perform(*args, **kwargs)` was forwarding submission positionally into `Llm::Request.call(**args)` which is kwargs-only → ArgumentError before instance was created → eternal spinner. Restored `(submission, **job_args)` convention. |
| 1646–1647 | **`config/llm.yml` actually loads `viva_turn_service` / `viva_grade_service`.** They were at the top level outside `&services`, so `Rails.application.config_for(:llm)` never saw them. Moved into the anchor; added `LLM_NON_SERVICE_KEYS` skip-list in cafe_grader initializer so they don't get treated as per-model registrations. |
| 1648–1649 | **`Llm::Request.preview(**args)` console helper.** Builds the LLM payload (whatever `prepare_data` produces) without making the network call or touching DB records. |
| 1650–1651 | **Viva consolidate same-role runs + require llm_prompt tag.** Backend collapses adjacent same-role string-content messages with `\n\n` (Anthropic Claude refuses consecutive same-role; OpenAI/Gemini accept but with degraded behavior). VivaTurnAssist#assemble_system_prompt and VivaGradeAssist#assemble_context now raise if the problem has no llm_prompt tag (matches CommentAssist behavior). |
| 1652–1653 | **Problem PDF included in viva first user message** (parity with CommentAssist). `pdf_attachment` lifted from CommentAssist to Llm::Request so both flows share it. |
| 1654–1655 | **`Llm::Request.preview` redacts long base64.** Multi-MB base64 PDFs in the preview output collapse to `<application/pdf base64, ~143KB redacted>`. Pass `redact: false` for raw. |
| 1656–1657 | **Grounding moves from system → first user message** for the interviewer. Removes the auto-injected "first user message contains the scenario..." paragraph (redundant with what any well-written viva prompt already says). DONE_SENTINEL directive extracted into a clearly-named private method (`done_sentinel_directive`). |
| 1658–1659 | **Viva assistant turns render as markdown** via new `safe_markdown` helper (Redcarpet with `filter_html: true` so prompt-injection-via-HTML can't execute). |
| 1660–1663 | **/submissions/:id/viva visual polish** — problem name moved into right-side Viva Info card, Turns count added, "Submission details" link added (later removed when we noticed it loops back). |
| 1664–1665 | **Polling preserves scroll position.** sessionStorage hand-off so outerHTML replacement doesn't reset scrollTop on every 3s tick. Initial page load auto-scrolls to bottom (chat convention). |
| 1666–1667 | **Grade error diagnostics.** `viva_grade.llm_response_raw` is saved BEFORE JSON parse, so failed grades preserve the raw model output. New `extract_json_object` is balanced-brace-aware and tolerates markdown fences + leading prose. |
| 1668–1671 | **`Problem#viva_setup_errors`.** Validates the llm_prompt tag has a `# Rubric` section before letting `VivaSessionsController#start` create the submission. Description checks were added then dropped — scenario lives in PDF, not description. |
| 1672–1673 | **`:evaluating` state handled correctly** in both controller and view. Answer form hides during evaluating, polling continues until grade lands or fails. `#answer` rejects late submissions during evaluating to prevent transcript desync. |
| 1674–1675 | **Viva session view dispatches on submission status**, not on viva_grade presence. Fixes the bug where rev 1666's early-save left the grader_error case rendering an empty grade card instead of the red error alert. |
| 1676–1677 | **Editor "raw response" panel moves into the right-side admin card** instead of inline in the chat area. Renamed Re-grade → Re-run grading. |
| 1678–1679 | **Total row baseline-aligned** in the grade card so the small "Total" label lines up with the bottom of the big number. |
| 1680–1681 | **Admin / Debug split into two cards.** Admin card has actions only. Debug card has: last grader run summary, grader response, grader request payload preview, turn request payload preview, per-turn responses (each `viva_turn.llm_response_raw` collapsible). Removed the dead "Submission details" link. |
| 1682–1683 | **Re-run grading model picker.** Form_with-based input-group: model dropdown (KNOWN_MODELS roster) + Re-run button. `SubmissionsController#rejudge` accepts `model:` param and passes through to `Llm::VivaGradeAssistJob.perform_later(submission, model: ...)`. KNOWN_MODELS = [] on master abstract; chula_cp's VivaGradeGenieAssist populates with the 8 Genie-supported models. |

### What's working end-to-end now

- Viva start: `Problem#viva_setup_errors` checks llm_prompt has `# Rubric`; redirects with clear flash message if not.
- Viva turn: PDF + scenario + grounding all delivered in one consolidated user message; transcript turns alternate cleanly; markdown rendered safely; scroll position preserved across the 3s polling refreshes.
- Viva end: `[[VIVA_DONE]]` triggers grading; submission flips `:evaluating`; UI shows "Grading in progress…"; polling continues; answer form is suppressed (no more transcript desync risk).
- Grade landing: `:done` state renders the grade card; `:grader_error` renders a red alert; in both cases the editor Debug card shows raw response + cost + model.
- Admin re-run: model picker on the Admin card lets editors retry with a stronger model; Solid Queue worker can be restarted between attempts to pick up code changes.
- Solid Queue dashboard: `/grader_processes/queues` filterable by status; failed jobs show the exception detail + backtrace.

## Remaining tasks (prioritized)

### 1. **`hg push`** — none of the work above has been pushed to GitHub

```bash
hg push     # mirrors both `master` and `chula_cp` bookmarks via hg-git
```

Master is at 1682, chula_cp at 1683 — about ~50 commits unpushed. Should
be done before machine switch so the work is mirrored remotely.

### 2. **Recover #922237's grade**

The submission has been sitting in `:grader_error` for the day. The
`gemini-2.5-flash` grader returned prose instead of JSON. Two fixes the
user can drive:

(a) **Add `# Rubric` to test_viva's llm_prompt tag content.** The grader
uses the same llm_prompt tag as the interviewer; without an explicit
Rubric section, the grader has nothing concrete to score against and
tends to produce vague prose. Run from console:

```ruby
prob = Problem.find_by(name: "test_viva")
tag = prob.viva_prompt_tags.first
tag.update!(params: tag.params + <<~RUBRIC)

  # RUBRIC
  Score the student on these criteria (0-100 each):
  - **Concept understanding**: Can they explain the underlying mechanism?
  - **Application**: Can they apply the concept to the scenario?
  - **Communication**: Are their answers clear and precise?
RUBRIC
```

(b) **Use the model picker.** Open `/submissions/922237/viva` as an editor.
In the Admin card dropdown pick `gemini-2.5-pro`. Click Re-run grading.
Pro is much more strict about following "respond ONLY with valid JSON".
If it fails again, the new failure's raw response replaces the old one
in the Debug card → expand "Grader response (last run)" to see what
`gemini-2.5-pro` returned. Pasting that text into chat lets us decide
what the next prompt-fix is.

Note: the Solid Queue worker must be restarted before retrying so it
picks up the code from rev 1682–1683 (model param threading).

### 3. **End-to-end UI smoke** (still not done formally)

- Master smoke (with `viva_turn_service:` blank in `config/llm.yml`): start
  a viva on `test_viva`. Expected: `viva_setup_errors` blocks on missing
  Rubric; once that's fixed, the abstract `VivaTurnAssist#execute_call`
  raises `NotImplementedError`, the placeholder turn flips to `:error`
  within ~3s with the formatted error message, and `/grader_processes/queues`
  filter "Failed" shows the job with full exception detail.
- Retry-no-flicker: stub `execute_call` to raise `Faraday::TimeoutError`
  once then succeed. Expected: turn never flips to `:error` mid-retry.
- Comment-assist on chula_cp: smoke a comment-assist via the UI, verify
  Comment#cost = 10 (the score penalty restored after rev 1655's fix).

### 4. **Update test_viva's `llm_prompt` tag** to drop the `{{...}}` literals

The current prompt has `{{TOPIC_NAME}}`, `{{MAX_TURNS}}`,
`{{TARGET_BLOOM_LEVEL}}`, etc. that the backend doesn't substitute. The
literal `{{...}}` strings are sent to the LLM as-is. The user agreed
during the design discussion to relax the prompt language to just say
"the description below contains topic, scenario, max turns, and difficulty
in some form — use what you can find" instead of the rigid template
syntax. That's prompt-author work, not code.

### 5. **Optional: items deferred during planning**

Lower priority, won't block normal use:

- **D — Stuck-turn watchdog.** If a worker dies between `service.call` and
  the turn-update DB write, the placeholder stays `:processing` forever.
  A periodic sweep ("any turn `:processing` for >120s gets marked `:error`")
  would prevent the residual eternal-spinner case. Solid Queue's default
  retry/discard semantics cover the common cases; this is for hard worker
  crashes.
- **G — Retry/discard buttons on `/grader_processes/queues`.** Per-row
  buttons that call `SolidQueue::FailedExecution#retry` / `#discard` from
  the admin dashboard. Currently you have to use the rails console.
- **Cosmetic: status-column badges** (red for failed, blue for running,
  etc.) in the queues table. Small JS column-renderer change.
- **Persist `llm_request_raw` on viva_grade** (not just `llm_response_raw`).
  Currently the Debug card's "Grader request payload (next run)" is
  reconstructed via `Llm::Request.preview` — it matches the actual sent
  request as long as the transcript hasn't changed since the run, which
  it usually hasn't. Storing the historical request would close the gap.
- **Extract VivaGradeAssist's grading_system_prompt heredoc** into a
  cleaner method. The hardcoded English is "policy" (JSON schema, role)
  rather than just contract (DONE_SENTINEL), so it doesn't need to be
  prompt-author-editable, but it's still a stylistic improvement.

## How to resume on the new machine

```bash
# Pick up where this branch left off
hg pull && hg update chula_cp                # or master, but chula_cp is what to run
bin/rails db:migrate                          # in case there are new migrations
bundle install                                # in case Gemfile changed
bin/dev                                       # starts server + worker

# When you switch to master to make a code change, switch back to chula_cp
# before running anything (server / worker). Master is missing
# Llm::VivaTurnGenieAssist + the 4 other genie files; running anything
# while on master breaks autoload for the worker.

# Read this doc + recent hg log to remember the rev numbers:
hg log --limit 50 --template "{rev} [{bookmarks}]: {desc|firstline}\n"
```

## Useful console snippets (frequently re-used)

```ruby
# Inspect a viva submission
sub = Submission.find(922237)
sub.viva_turns.ordered.each { |t| puts "##{t.id} #{t.role}/#{t.status}: #{t.content.to_s[0,80]}" }
sub.viva_grade.attributes.slice("total_points", "narrative", "llm_response_raw")

# Preview the next grader request (what would be sent)
require "json"
puts JSON.pretty_generate(Llm::VivaGradeGenieAssist.preview(submission: sub))

# Preview the next viva-turn request
puts JSON.pretty_generate(Llm::VivaTurnGenieAssist.preview(submission: sub, turn: nil))

# Retry a failed Solid Queue job
SolidQueue::FailedExecution.find(<id>).retry

# Find the failed grader job for a submission
SolidQueue::FailedExecution
  .joins(:job)
  .where("solid_queue_jobs.class_name LIKE ?", "Llm::VivaGrade%")
  .last
```

## Files of interest (where the LLM/viva logic lives)

```
app/services/llm/
  request.rb              # abstract base — call template, rescue, pdf_attachment, preview helper
  comment_assist.rb       # comment-on-submission shape (master)
  viva_turn_assist.rb     # viva interview turn shape (master)
  viva_grade_assist.rb    # viva grading shape (master, includes KNOWN_MODELS = [])

  # chula_cp only:
  genie_assist.rb              # GenieAssist < CommentAssist (Chula Genie auth + endpoint)
  viva_turn_genie_assist.rb    # VivaTurnGenieAssist < VivaTurnAssist
  viva_grade_genie_assist.rb   # VivaGradeGenieAssist < VivaGradeAssist (KNOWN_MODELS = 8 models)
  token_manager.rb              # Genie bearer-token cache

app/jobs/llm/
  request_job.rb          # abstract — retry policy, perform(submission, **kwargs)
  comment_assist_job.rb   # marker base for comment-style jobs (master)
  viva_turn_assist_job.rb # configured via Rails.configuration.llm[:viva_turn_service]
  viva_grade_assist_job.rb

app/controllers/
  viva_sessions_controller.rb  # start / show / answer / refresh + load_viva_state
  submissions_controller.rb    # rejudge (handles viva re-grade with model: param)

app/views/viva_sessions/
  show.html.haml          # page shell + right-side cards (Info, Admin, Debug)
  _viva_session.html.haml # the chat area + answer form / grade / error rendering
  _turn.html.haml         # per-turn rendering (markdown for assistant)
  _answer_form.html.haml

app/javascript/controllers/
  viva_session_controller.js   # 3s polling + scroll-state hand-off

app/presenters/llm/
  request_job_presenter.rb     # used by /grader_processes/queues + /report

config/
  llm.yml                       # llm_services anchor with viva_turn_service, viva_grade_service
  initializers/cafe_grader.rb   # loads llm.yml; LLM_NON_SERVICE_KEYS skip-list

app/models/
  problem.rb              # Problem#viva_setup_errors, viva_prompt_tags
  user.rb                 # roles: admin, group_editor, reporter
```
