# Viva Test-Drive Sessions — Design

**Date:** 2026-09-23
**Status:** Approved in discussion (dae, 2026-09-23), pending spec review
**Implements:** the *test-drive* half of D7 in
`2026-07-20-viva-deployment-readiness-design.md` ("the author takes the viva
themselves in a session flagged as a test — excluded from reports, cost
dashboards, and attempt limits; unlimited restarts"). The other half of D7,
the preflight lint over the assembled prompt, stays open and is **not** part
of this design.

## The problem

The only real check of an LLM examiner is to sit the viva. A group editor can
already start a viva on a draft problem in their own groups (the `:edit` arm of
`User#can_submit_to_problem?`), but the session is a real submission in every
respect: it appears on the problem stat page, the Score / Submission / AI
reports and the contest AI-usage report; its LLM cost counts as student spend;
it uses one of the author's daily starts (admins skip that limit, editors do
not); and its transcript sits among student sessions for later audits and
regrades to trip over. Authors therefore either pollute the data every time
they test or test less than they should. `doc/Viva-Exam.md` lists this under
Known Gaps as "D7 … designed but not implemented".

## The model

**One flag.** `submissions.test_drive` — boolean, `NOT NULL DEFAULT false`. Set
only by the new test-drive start path (below); never by students, never by the
API, never editable afterwards. No index: every reader also filters by user /
problem / time, and the column is two-valued.

**One scope.** `Submission.regular` today means "not a near-miss shadow"
(`where(repaired_from_id: nil)`, `app/models/submission.rb:97`) and, by the
near-miss exclusion audit, is read by every student-facing list, score, quota
and report. It widens to

```ruby
scope :regular, -> { where(repaired_from_id: nil, test_drive: false) }
scope :test_drives, -> { where(test_drive: true) }
```

with its comment updated: *regular = a real, student-facing submission — not a
near-miss shadow, not an author's test-drive.* Every existing `.regular` call
site then excludes test-drives with no further change. `shadow` keeps its
meaning.

**Hand-written shadow checks that must gain the matching test-drive
condition** (they bypass the scope):

| where | today | change |
|---|---|---|
| `app/controllers/report_controller.rb:540, 551` (`cheat_report` raw SQL) | `AND s.repaired_from_id IS NULL` | `… AND s.test_drive = 0` |
| `app/controllers/report_controller.rb:593` (`cheat_scrutinize` raw SQL) | same | same |
| `app/models/problem_stat.rb:7` (LEFT JOIN condition) | `AND submissions.repaired_from_id IS NULL` | `… AND submissions.test_drive = 0` |
| `app/controllers/main_controller.rb:119` (`source`) and `:137` (`load_output`) | owner ∧ not shadow | owner ∧ not shadow ∧ not test-drive is **not** needed — the owner may see their own test-drive; leave as is |
| `app/models/user.rb:486-500` (`can_view_submission?`) | shadows denied to everyone below admin/reporter; archived vivas denied to peers | test-drives stay visible to their **owner** (the author) and to admins/reporters, and are denied to every other student **even when the problem's `view_submission` sharing flag is on** — a new `return false if submission.test_drive?` sits beside the archived-viva branch (after the owner short-circuit, before the sharing check). Without it a peer could read the author's probing of the rubric on a problem that shares transcripts. |
| `app/models/ai_usage_report.rb:163` (`sub_ids`) | `Submission.where(problem_id:, user_id:)` — no scope | `Submission.regular.where(…)` |

**Readers that must NOT filter** (unchanged, as for shadows): the judge worker
and job plumbing, `Submission.find` on detail pages, admin monitoring pages
(grader processes, stuck turns, viva alerts), `viva:*` rake tasks that operate
on an explicit submission, the 24 h reaper, and number assignment.

## Who may start one, and what it skips

A new action `VivaSessionsController#test_drive` (`POST
/problems/:id/viva/test_drive`, route name `viva_test_drive_problem`). Gate:
`@current_user.can_edit_problem?(@problem)` — admins and editors of a group the
problem belongs to (`User#can_edit_problem?`, `app/models/user.rb:439`).
Everyone else gets the same "Authorization error" redirect `#start` uses.

Compared with `#start`, a test-drive **skips**:
1. the one-active-session guard — but only across *real* sessions: an author
   may hold one open test-drive per problem; a second click while one is open
   redirects to the open one instead of creating another;
2. the daily start limit (`daily_start_limit_for` / `engaged_starts_today`);
3. the contest-only rule (`viva_daily_limit == 0` ⇒ contest mode required).

It **keeps**: `viva_exam?`, the viva language check, and `viva_setup_errors`
(a viva with no briefing cannot assemble a prompt; the test-drive is for
behaviour, not for structural gaps the form already reports).

Session creation is extracted from `#start` into one private method
`create_viva_session!(test_drive:)` (system "(interview start)" turn, assistant
placeholder, `Llm::VivaTurnAssistJob` after the transaction) so `#start`,
`#test_drive` and the test-drive restart share it. The interview and grading
pipeline is untouched: same prompt assembly, same models, same grade record,
same alert detection. That is the point — what the author sees is what a
student would see.

**Restart** (`#restart`) on a test-drive archives the session (`viva_archived_at`)
and immediately creates a fresh test-drive, redirecting to it, instead of
sending the author to the problem list with a limit notice.

**End interview** (`#finish`) on a test-drive drops the "contest vivas cannot
be ended early" refusal; everything else (owner-only, lock, no-answer refusal)
stays.

## UI

**Problem edit page header** (`app/views/problems/edit.html.haml`, the pill row
next to Stats / Download / History / Help). For `@problem.viva_exam?` only: a
labeled pill button **"Test-drive"** with icon `play_circle`, Flavor A
`button_to viva_test_drive_problem_path(@problem)`, `data-bs-title` "Take this
viva yourself in a test session — excluded from reports, cost figures and
start limits". Labeled, not icon-only, for the same reason Help is: authors
must discover it. It lives in the header because the Viva Exam card sits
inside the ONE problem form and a nested form is invalid HTML.

**Viva Exam card** (`app/views/problems/_viva_fields.html.haml`, viva layout
only — not the inline block shown when switching a regular problem to viva): a
new read-only section **"Test-drives"** under Interview setup listing the
problem's test-drive sessions, newest first, at most 10: author login, started
(time ago), status, points or "—", "test-drive" badge, link to the session.
Empty state: "No test-drives yet — use the Test-drive button above." Visible to
whoever can see the edit page (editors and admins).

**Viva session page** (`app/views/viva_sessions/show.html.haml`):
- badge `test-drive` (info colour) beside the status, next to the existing
  `archived` badge;
- the Starts row reads "Test-drive — unlimited restarts; excluded from reports,
  cost figures and start limits";
- the Restart button reads "Restart test-drive" and its confirm says the fresh
  session opens at once;
- End interview is offered on test-drives regardless of `viva_daily_limit`;
- the `_viva_session` partial is unchanged (transcript, answer form, grade card).

**Admin surfaces show test-drives with a badge, never hide them:** the viva
alerts page (`graders#viva_alerts` — an author probing jailbreak resistance
wants to see the alert fire), stuck viva turns. The per-user page under User
Admin and the problem stat page are *reports* and already read `.regular`, so
they exclude test-drives like every other report. One helper `submission_test_drive_badge(sub)` (in
`SubmissionsHelper`, created if absent) renders the badge.

## Interactions

- **Finish open vivas** (rev 2161) reads `Contest#submissions` = `.regular` →
  leaves test-drives alone, even an admin's mid-contest one.
- **24 h reaper** does not use `.regular` → a forgotten test-drive is graded a
  day later. Accepted: one grade call, and the author gets the grade.
- **Daily-limit accounting** (`engaged_starts_today`, `.regular`) → an
  author's test-drives never consume their own real starts.
- **Near-miss** — `batch_targets` reads `.regular` → test-drives are never
  repair targets. Viva is already excluded from repair (D8 of that design).
- **API** (`/api/v1`) lists read `.regular` → test-drives never appear; the API
  has no viva start endpoint, so it cannot create one.
- **Contest score report / scoreboard** read `.regular` → excluded.
- **Cost figures** — the AI-usage report gains `.regular`; the problem / user
  stat pages' per-model request/points/dollar tables already go through
  `.regular` submissions; `viva_turns` / `viva_grades` rows still exist and any
  hand-run SQL over them must join submissions and filter `test_drive = 0`
  (noted in `doc/Viva-Exam.md`).
- **Alerts** — detection runs unchanged; the exam-strict consequence branch is
  dormant (Phase B) so nothing to gate. When Phase B lands, test-drives must
  take the *practice* (log-only) branch regardless of contest — recorded as a
  Phase B requirement in `doc/Viva-Exam.md`.
- **Import/export, kit importer** — untouched.

## Explicitly rejected

- **A test-drive condition at every call site instead of widening `regular`.**
  Same result, dozens of edits, and the next report author forgets one. The
  scope is the single definition of "real submission"; that is why it exists.
- **Modelling test-drives as near-miss shadows** (`repaired_from_id` = self or
  a sentinel). Reuses the mechanism but breaks what a shadow means (a repaired
  copy of a real submission), corrupts `SubmissionRepair` stats, and hides the
  session from its own author.
- **A separate "test session" table.** The interview/grade pipeline keys on
  `Submission`; duplicating it for one flag is not worth it.
- **Test-drive as a per-problem toggle** (the retired `viva_mode` mistake): a
  flag an author can leave on. Per-session flags cannot be forgotten.
- **Auto-purge of old test-drives.** Volume is small; restart archives them;
  revisit if the list ever matters.

## Data & migration

```ruby
add_column :submissions, :test_drive, :boolean, null: false, default: false
```

MySQL 8 performs this as an instant metadata change (appended column with a
default), so it is safe on production's submissions table during a deploy.
No backfill: nothing existing is a test-drive.

## Tests

- **Model** (`test/models/submission_test.rb`, `test/models/user_test.rb`):
  `regular` excludes a test-drive and a shadow; `test_drive` scope;
  `can_view_submission?` — owner sees own test-drive, another student does
  not even with `view_submission` on, admin/reporter do.
- **Controller** (`test/integration/viva_sessions_controller_test.rb`):
  `test_drive` by an editor of the problem's group creates a flagged session
  and redirects to it; by a non-editor student → authorization redirect and
  no submission; skips the daily limit (limit 1, one engaged real session
  today, test-drive still starts); skips the contest-only rule
  (`viva_daily_limit = 0`, contest mode off); second click with one open
  test-drive redirects to it; restart archives and opens a fresh flagged
  session; finish allowed on a contest-only test-drive.
- **Exclusion** (existing report tests + new cases): a test-drive with 100
  points does not change the main list's shown score, the contest score
  report, `Problem#stat`-style counts, `ProblemStat.recompute_all`, the
  AI-usage report's session/cost totals, or `cheat_report` rows.
- **Views** (`test/integration/problems_controller_test.rb`): the Test-drive
  button appears on a viva problem's edit page for an editor and not on a
  code problem; the Test-drives list shows a session with the badge.
- **System** (optional, `test/system/viva_sessions_test.rb`): editor clicks
  Test-drive, lands on a session page carrying the badge.

## Docs (same commit as the code)

- `doc/Viva-Exam.md`: new section "Test-drive sessions" (what, who, what is
  skipped, where to find them, the hand-SQL rule); Known Gaps D7 line split —
  test-drive DONE (rev), preflight lint still open; Phase B requirement noted.
- `doc/wiki/viva-authoring-guide.md`: new section "Test-drive before
  publishing" + a pitfalls-table row ("published without sitting it once").
  Deployment-neutral wording.
- `doc/wiki/instructor-viva-guide.md`: a short "Test-driving a viva" section
  under Authoring.
- `doc/Viva-History.md`: entry (Problem → Change → Outcome), citing the rev
  and this spec.
- `CHANGELOG.md` `[Unreleased]` → Added.
- `doc/backlog.md`: no entry exists; nothing to move. Add a "Waiting for a
  signal"-style pointer for the preflight lint half only if dae wants it
  tracked there (default: it stays in Viva-Exam's Known Gaps).

## Out of scope

- The D7 preflight lint (LLM pass over the assembled prompt).
- Any change to how students start, restart or are limited.
- Phase B (contest retake budgets, snapshot, window-end force-finish).

## Deviations recorded during execution (2026-09-23)

- The scope is `Submission.test_drives` (plural) so the class-level scope is never confused with the per-row `test_drive?` reader.
- No badge on `submissions/show`: that page redirects every viva submission to the viva page (`SubmissionsController#show`), so a test-drive can never render there. The badge lives on the viva session, viva alerts and stuck-turns pages.
- The admin problem index (`problems/index`) offers **Test-drive** on viva rows instead of the former staff "Start Viva" — the real-session path that polluted the data this feature protects. Real sessions start from the student-facing main list only.
- `#restart` runs under the submission row lock (a double click no longer opens two test-drives) and re-runs the setup check before opening the fresh session. `#test_drive` authorizes before it inspects the problem, and reopens only a test-drive whose interview or grading is still in progress; a graded one no longer blocks a fresh start.
- The hand-SQL rule is recorded in `doc/Viva-Exam.md` only: Assist-History's "Numbers for reporting" table counts assist comments, which a viva test-drive cannot carry.
