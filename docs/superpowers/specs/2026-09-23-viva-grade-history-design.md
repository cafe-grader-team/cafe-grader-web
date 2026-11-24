# Viva Grade History — Design

**Date:** 2026-09-23
**Status:** Approved in discussion (dae, 2026-09-23), pending spec review
**Implements:** the backlog entry "Viva grade history — make 'regrade' a
feature instead of a script" (`doc/backlog.md`, raised 2026-09-09). Replaces
the hand-run toolkit
`course-prep/data-structures/viva/regrade-cell-detection-2026-09-09/tools/regrade_tool.rb`
(snapshot / regrade / status / finalize / restore / verify / report) with
in-app equivalents. The never-lower rule and the whole-record rule are the
ones decided on 2026-09-09 (`doc/Viva-History.md`).
**Companion figure:** `tmp/erd-viva-grades.html` (hg-ignored; AS-IS and TO-BE
ERDs, regenerate from the session script if needed).

## The problem

`viva_grades` holds one row per submission (unique index on `submission_id`).
`Llm::VivaGradeAssist#handle_response` builds that row or reuses it; the admin
**Re-run grading** button (`SubmissionsController#rejudge`) destroys it, sets
the submission back to `evaluating` with `points: nil`, and enqueues a new
grading job. Consequences:

- The app keeps no grade history. A regrade of a cohort after a briefing
  change (Cell Detection, 2026-09-09: 157 sessions) needed an external
  before-image to be reversible, a hand-written max(old, new) step, and a
  verify pass — all outside the app.
- A failed re-run (grader returned prose, provider 403) leaves the student
  with no grade at all: the old row is already gone.
- `viva_grades.rubric_version` exists and is never written, so nothing
  records which briefing graded a session and a batch cannot tell a stale
  grade from a fresh one.
- The 2026-09-09 run measured re-run noise at SD 4.2 points on identical
  transcripts, so "never lower" is not a nicety: without it a rubric fix
  would lower some students' grades by luck.

## The model

**One row per grader run.** A grader run is one call of the grade job for one
submission: the automatic grading at the end of an interview, an admin
Re-run, or one member of a batch regrade. Every run writes its own
`viva_grades` row and no row is ever destroyed.

**The current grade.** The row with `superseded_at IS NULL` is the
submission's current grade — the run whose `total_points` is copied to
`submissions.points`. At most one current row per submission. MySQL cannot
enforce "at most one NULL" with an index, so the model enforces it: a
uniqueness validation on `submission_id` conditioned on `superseded_at: nil`,
and every state change runs inside the submission's row lock
(`Submission#with_lock`, the pattern `#finalize_open_viva!` already uses).

**New columns on `viva_grades`** (all nullable):

| column | type | meaning |
|---|---|---|
| `superseded_at` | datetime | when this run stopped being current, or was decided against. NULL = current |
| `superseded_reason` | string | why it is not current: `replaced` (a later run was adopted), `lower` (never-lower kept the older grade), `error` (this run failed), `reverted` (displaced by Make current or a batch revert). NULL while a run is being written and not yet decided |
| `superseded_by_id` | integer | for `replaced` and `reverted`: the row that took its place. Makes a batch revert possible |
| `requested_by_id` | integer | the user who clicked Re-run or Make current; NULL for automatic grading and for batch runs |
| `batch_id` | string | the `viva:regrade` batch this run belongs to; NULL for single runs |
| `error` | text | the grader failure message, failed runs only (the same text that goes to `grader_comment` today) |

`rubric_version` (existing, string) is now written on every run: the SHA-256
hex digest of the grader's rubric context — the exact string
`assemble_context` builds (conduct tags + briefing + grounding text). Computed
by a new class method `Llm::VivaGradeAssist.rubric_version_for(problem)`,
which `assemble_context` and the batch task both use, so "stale" means
"graded under a different context than the problem has now". Existing rows
have `rubric_version NULL` and count as stale.

**Index change:** the unique index on `submission_id` is dropped; a non-unique
index on `(submission_id, superseded_at)` and an index on `batch_id` are
added.

**Associations:**

```ruby
# Submission
has_many :viva_grades, dependent: :destroy
has_one  :viva_grade, -> { where(superseded_at: nil) }   # the current grade

# VivaGrade
belongs_to :submission
belongs_to :superseded_by, class_name: 'VivaGrade', optional: true
belongs_to :requested_by,  class_name: 'User',      optional: true
REASONS = %w[replaced lower error reverted].freeze
scope :current, -> { where(superseded_at: nil) }
scope :history, -> { where.not(superseded_at: nil) }
def current?      = superseded_at.nil?
def valid_grade?  = total_points.present?
def failed?       = !valid_grade?
def supersede!(reason:, by: nil, now: Time.zone.now)
```

`validates :submission_id, uniqueness: true` is removed and replaced by the
conditional uniqueness above. `superseded_reason` validates inclusion in
`REASONS`, nil allowed.

## How a run is written and adopted

**Every run is written non-current first, then decided.** `handle_response`
holds the row it is writing in `@grade` (never `@submission.viva_grade`, which
is now the current grade and must not be overwritten):

1. `@grade ||= @submission.viva_grades.build(superseded_at: now,
   requested_by_id:, batch_id:, rubric_version:)`. Raw response, model, cost,
   timing are assigned and saved before any parsing, as today, so a failure
   leaves a paper trail. The one automatic re-ask reuses `@grade` and folds
   its cost in, as today.
2. Parse and schema-check, as today. On success write `score_json`,
   `total_points`, `narrative`.
3. **Decide**, inside `@submission.with_lock`, reading the current grade
   fresh:

| current grade at decision time | never-lower | outcome |
|---|---|---|
| none, or a failed run | any | **adopt**: `@grade.superseded_at = nil`; submission `points`, `status: :done`, `graded_at`, `grader_comment` = viva marker (today's write) |
| valid, `new >= old` | any | **adopt**; old row `supersede!(reason: 'replaced', by: @grade)` |
| valid, `new < old` | on | **keep old**: `@grade.superseded_reason = 'lower'`; submission untouched |
| valid, `new < old` | off | **adopt**; old row `replaced` |

Equal totals adopt the new run (the 2026-09-09 tool did the same). "Adopt"
is one method, `Submission#adopt_viva_grade!(grade, reason: 'replaced')`,
also used by Make current and by the batch revert; it refuses a failed run
and a run of another submission.

**Failure paths never take a grade away.** A run fails when the reply is not
a grade after the re-ask (`handle_error`) or when the job's retries are
exhausted (`Llm::VivaGradeAssistJob#on_retries_exhausted`; retryable
transport errors never reach `handle_error`). Both call one class method,
`VivaGrade.record_failure!(submission, error:, model:, requested_by_id:,
batch_id:)`, which marks `@grade` (or creates a row when nothing was saved)
with `superseded_reason: 'error'` and the message in `error`. The submission
is set to `grader_error` with the message in `grader_comment` **only when it
has no valid current grade** — today's behaviour for a first grading. When a
valid grade exists, the submission stays `done` with its grade and the failed
run shows in the history table.

**Starting a regrade** is `Submission#regrade_viva!(model: nil, never_lower:
true, requested_by: nil, batch_id: nil)`:

- refuses (raises `Submission::NotRegradable`) unless the problem is a viva
  and the submission is `done`, `grader_error` or `evaluating` — an open
  interview (`submitted`) must be ended first; today's button lets an admin
  grade a half-finished interview;
- inside the row lock: when there is no valid current grade (none at all, or
  the first grading's failed run is still the newest), the submission goes
  `status: :evaluating, points: nil, graded_at: nil, grader_comment: nil` as
  today, so the student sees "Grading in progress" and the stuck-grading
  sweeper applies. When a valid grade exists the submission is **not
  touched**: the student keeps seeing their grade until a new run is adopted;
- after the lock: `Llm::VivaGradeAssistJob.perform_later(self, **kwargs)`
  with only the non-nil kwargs (`model`, `never_lower`, `requested_by_id`,
  `batch_id`). `Llm::VivaGradeAssist#initialize` gains the three new
  keyword arguments with defaults (`never_lower: true`, others nil), so the
  four existing first-grading call sites (End button, hard cap, Finish open
  vivas, the 24-hour reaper) change nothing.

**Concurrency.** Two runs in flight for one submission each write their own
row and decide under the lock against whatever is current at that moment;
the second decision sees the first's result. A double click on Re-run
produces two runs, which is wasteful but never wrong (the 2026-09-06 lock on
Answer/End covered the first-grading path; a lock on the button is not worth
it).

**Sweepers.** `Submission.fail_stale_viva_evaluating!` and the stuck monitor
keep `where.missing(:viva_grade)`; with the scoped `has_one` this now means
"no current grade", which is exactly a grading that never produced an
adopted run. A submission whose valid grade is current never enters
`evaluating` for a regrade, so the sweeper never touches it. The window in
which a run is saved non-current but not yet decided is milliseconds and the
sweeper's threshold is minutes; documented, not guarded.

## Surfaces

### Re-run grading (viva session page, Admin card)

The form keeps its model picker and gains a checkbox **Keep the higher
grade** (`never_lower=1`, checked by default): "if the new run scores lower,
the current grade stays and the run is kept in the history". Submit label
stays "Re-run grading"; the confirm becomes "Re-run grading? The current
grade is kept in the history." `SubmissionsController#rejudge`'s viva branch
calls `regrade_viva!(model: params[:model].presence, never_lower:
params[:never_lower] == '1', requested_by: @current_user)`; the toast names
the model and the rule; a `NotRegradable` on an open interview becomes an
`:alert` toast "End the interview before re-running grading".

### Grade history (viva session page, Admin card, below the form)

`viva_sessions/_grade_history.html.haml`, rendered for users who
`can_edit_problem?`, lists `@submission.viva_grades.order(graded_at: :desc,
id: :desc)`; one row per run:

| column | content |
|---|---|
| When | `graded_at` (time ago, full timestamp in the title) |
| Model | `llm_model` |
| Total | `total_points`, or "—" for a failed run |
| Rubric | first 8 hex of `rubric_version`, muted; "—" for legacy rows; a title tooltip says whether it matches the problem's current rubric |
| By | `requested_by.login`, or "batch `<batch_id>`", or "auto" |
| Outcome | badge: **current** (success) · replaced (secondary) · not adopted: lower (warning) · error (danger) · reverted (secondary) · not adopted (secondary, `superseded_at` set and reason nil) |
| actions | **Make current** (valid, non-current runs only) · **Raw** toggle |

**Make current** is a `button_to` with `turbo-confirm` ("Make this run the
current grade? The student's score and feedback change to this run.") to the
new route `POST /submissions/:id/viva/grades/:grade_id/adopt`
(`submissions#adopt_viva_grade`, guarded by `set_submission`, `set_problem`,
`can_edit_problem` like `rejudge`). It calls `adopt_viva_grade!(grade,
reason: 'reverted')` — the displaced run is labelled `reverted`, its
`superseded_by_id` points at the re-adopted run — then redirects to the viva
page with a notice, so the grade card and the table re-render together. It
is refused (alert) while the interview is open or grading is in flight
(`submitted`, `evaluating`). The **Raw** toggle opens a Bootstrap collapse
row showing `error` (if any) and `llm_response_raw` in a small `pre`. The
Debug card's "Last grader run" block and its raw-response section are
removed; the payload previews stay.

The student-facing grade card (`submissions/_viva_grade`) is unchanged.

### `bin/rails viva:regrade` (batch)

```
bin/rails viva:regrade PROBLEM=<name|id> [CONTEST=<name|id>] [MODEL=<model>]
                       [ALL=1] [REPLACE=1] [LIMIT=<n>] [APPLY=1]
```

Report-only unless `APPLY=1`, like `viva:import`. Backed by
`Viva::Regrader` (`app/services/viva/regrader.rb`), so tests exercise the
service, not the rake wrapper.

**Targets** (`Viva::Regrader#targets`):

- base: `Submission.regular.where(problem:)` — real student sessions:
  archived attempts **included** (their score can still be a student's max),
  test-drives and near-miss shadows excluded by `regular`;
- with `CONTEST=`: `contest.submissions.where(problem:)` instead —
  `Contest#submissions` is the existing membership-and-window scope
  (enrolled users, `submitted_at` inside the window with each user's start
  offset and extra time, `regular`). The problem must belong to the contest;
  otherwise the task aborts;
- status `done` (has a grade) or `grader_error` (first grading failed:
  listed separately as retries — they go through the `evaluating` path);
  `submitted` and `evaluating` sessions are skipped and counted;
- **stale only** unless `ALL=1`: a `done` target whose current grade is
  valid and whose `rubric_version` equals
  `rubric_version_for(problem)` is skipped as up to date. So a rerun after a
  crash grades only what is left, and a run with no briefing change reports
  "nothing to do" unless `ALL=1` (the case for "same rubric, different
  model");
- `LIMIT=<n>` takes the first n targets by id (rehearsal on a few sessions).

**Dry run prints:** problem (id, name), contest if any, the current rubric
version (first 12 hex), grader class and the model label (`MODEL` or
"default"), the rule (never-lower or replace), counts — targets, of which
retries, archived, skipped up to date, skipped open — and an estimated cost
(mean `cost` of the problem's current grades × targets, or "unknown" when
there is none), then the `APPLY=1` hint.

**`APPLY=1`:** `batch_id = "regrade-<problem.id>-<YYYYMMDDTHHMMSS>"`; each
target's `regrade_viva!(model:, never_lower:, batch_id:)`; one audit row
`AuditLog.record!(auditable: problem, action: 'viva_regrade',
object_changes: {batch_id, contest, model, never_lower, rubric_version,
targets, submission_ids})` with `Current.actor_note = "Rake: viva:regrade
<problem>"`; prints the batch id, the status command and the queue page
(`/grader_processes/queues`).

### `bin/rails viva:regrade_status BATCH=<id> [CSV=<path>]`

`Viva::Regrader.status(batch_id)` reads the audit row for the target list
and every `viva_grades` row of the batch. Per target: **old** = the grade
current before the batch (for an adopted run, the row whose
`superseded_by_id` is the new run; for `lower` and `error` runs, the still
current grade), **new** = the run's `total_points` (nil for error), **final**
= the current grade's total. Prints counts (adopted, kept lower, error,
pending = targets with no batch row yet, reverted), the old / new / final
means, up / equal / down counts, and with `CSV=` writes one line per target
(submission_id, login, archived, old, new, final, outcome). This replaces
the toolkit's `status` and `report`.

### `bin/rails viva:regrade_revert BATCH=<id> [APPLY=1]`

`Viva::Regrader.revert(batch_id, apply:)`: for every run of the batch that is
current, find the row it replaced (`superseded_by_id = run.id`) and
`adopt_viva_grade!(old, reason: 'reverted')`; a run with no predecessor (the
target had no valid grade before the batch) is left alone and counted as
"kept — no earlier grade"; `lower` and `error` runs need nothing. Report-only
unless `APPLY=1`; on apply, one audit row `viva_regrade_revert` on the
problem with the counts. Nothing is deleted: the reverted runs stay in the
history as `reverted`. This replaces the toolkit's `restore` + `verify`.

## Readers

| reader | today | change |
|---|---|---|
| `Submission.stuck_viva_evaluating` / `fail_stale_viva_evaluating!` (`where.missing(:viva_grade)`) | no grade row | no code change; now means "no current grade" (see Sweepers) |
| `AiUsageReport#grade_calls` (`VivaGrade.where(submission_id:, graded_at:)`) | every row | no filter added — every run cost money; `status` becomes `'error'` when `total_points` is nil instead of a hard-coded `'ok'` |
| `Viva::GraderCommentCleaner` (`joins(:viva_grade)`) | the row | the current row; no change |
| viva session page (`load_viva_state`: `@viva_grade = @submission.viva_grade`) | the row | the current row; grade card unchanged; history table added for editors |
| `_viva_grade` partial, main list, score reports, contest reports, API | `submissions.points` | unchanged |
| `Llm::Request.preview` (Debug card payload preview) | `new(submission:)` | unchanged; new kwargs have defaults |

## Contest reports bucket on session start — a rule, not a caveat

`doc/viva-visibility.md` lists it as a caveat that contest reports bucket a
viva by `submitted_at` (session start), not by when grading finished. This
design depends on that: a regrade adds a run weeks after the session, and
the session must stay in the contest window where the student took it.
`submissions.graded_at` moves to the adopted run's time; `submitted_at`
never moves. The paragraph is rewritten as the rule with this rationale.
What remains of the old caveat is operational — first grading lands minutes
after the bell — and is covered by the Finish-open-vivas button (rev 2161)
plus the queue page; a small backlog entry asks for an in-flight grading
count on the contest page so staff can see when a score table is final.

## Explicitly rejected

- **A separate archive table** for old grades: the current row would stay
  unique, but never-lower means moving whole rows back and forth between
  two tables, and every reader that wants history would join two tables.
- **A boolean `current` flag** instead of `superseded_at`: the timestamp
  carries the flag and the when.
- **A placeholder row at enqueue time** ("pending"): would change the write
  path of all four first-grading call sites and the sweeper's test; the
  queue page and the batch status task give the same visibility.
- **A student-facing "regraded" note**: under never-lower the total only
  rises, but the feedback text changes wholesale; the instructor frames
  cohort regrades. A "Graded on <date>" line can be added later without a
  schema change.
- **Auditing single re-runs in `audit_logs`**: the grade row itself carries
  who and when (`requested_by_id`, `graded_at`); the batch is audited on
  the problem because it is one intent over many rows (the CLAUDE.md
  consolidation rule).
- **A row lock on the Re-run button**: a double click yields two runs, both
  decided correctly under the lock; the cost is one grading call.
- **Deleting anything**, including on revert.

## Data & migration

```ruby
class AddHistoryToVivaGrades < ActiveRecord::Migration[8.0]
  def change
    change_table :viva_grades, bulk: true do |t|
      t.datetime :superseded_at
      t.string   :superseded_reason
      t.integer  :superseded_by_id
      t.integer  :requested_by_id
      t.string   :batch_id
      t.text     :error
    end
    remove_index :viva_grades, name: 'index_viva_grades_on_submission_id'
    add_index    :viva_grades, [:submission_id, :superseded_at]
    add_index    :viva_grades, :batch_id
  end
end
```

Existing rows need no backfill: `superseded_at NULL` makes each the current
grade of its submission (there is exactly one per submission today), and
`rubric_version NULL` makes them stale, so the first `viva:regrade` on a
problem targets everything, as the 2026-09-09 run did. Production
`viva_grades` is in the low thousands of rows; the DDL is quick.

## Tests

- **Model** (`test/models/viva_grade_test.rb`, new; `test/models/submission_test.rb`):
  at most one current row per submission (validation); `supersede!`;
  `adopt_viva_grade!` copies points / status / graded_at / marker, labels
  the displaced row and refuses a failed run; `regrade_viva!` leaves a
  submission with a valid grade untouched, moves a `grader_error` one to
  `evaluating`, refuses an open interview, enqueues with only the given
  kwargs; `where.missing(:viva_grade)` treats a submission with only
  superseded rows as missing (`fail_stale_viva_evaluating!` regression).
- **Service** (`test/services/llm/viva_grade_assist_test.rb`, stubbed
  `execute_call`): first grading adopts and writes `rubric_version`; higher
  regrade replaces (old row `replaced`, `superseded_by_id` set); lower
  regrade with never-lower leaves the submission untouched and stores a
  `lower` row; lower regrade with never-lower off replaces; equal adopts;
  failed regrade over a valid grade stores an `error` row and keeps
  `status: done`; failed first grading still ends in `grader_error`; the
  re-ask folds cost into the same row; `rubric_version_for` changes when
  the briefing or a conduct tag changes.
- **Job** (`test/jobs/llm/viva_grade_assist_job_test.rb`, new or existing):
  `on_retries_exhausted` over a valid grade records an `error` row and does
  not touch the submission; without one, `grader_error` as today.
- **Regrader** (`test/services/viva/regrader_test.rb`, new): targets are
  stale-only by default and everything with `ALL`; archived included,
  test-drives excluded, `grader_error` counted as retries, open sessions
  skipped; `CONTEST` restricts to the contest's window and members and
  aborts on a foreign problem; `apply!` enqueues one job per target with
  the batch id and writes the audit row; `status` computes old / new /
  final and pending; `revert` re-adopts predecessors, labels the displaced
  runs `reverted`, leaves runs without a predecessor, and is report-only
  without apply.
- **Controller** (`test/integration/submissions_controller_test.rb`):
  rejudge passes `never_lower` and `requested_by_id` to the job; rejudge on
  an open interview returns the alert toast; the existing "swept to
  grader_error can be regraded" test still passes; `adopt_viva_grade`
  needs `can_edit_problem`, refuses a failed run, redirects with the grade
  card showing the adopted total.
- **View** (`test/integration/viva_sessions_controller_test.rb`): the
  history table renders one row per run with the right badges for an
  editor and not for the student.
- **Report** (`test/models/ai_usage_report_test.rb`): a superseded run's
  cost is counted; a failed run reports `error`.
- Existing tests that build a `viva_grade` via `has_one` (`build_viva_grade`,
  `create_viva_grade!`) keep working because the scoped `has_one` remains.

## Docs (same commit as the code)

- `doc/Viva-Exam.md`: Grading section — one row per run, the current grade,
  `rubric_version`; Admin actions — Re-run rewritten (no longer destroys;
  the checkbox), Make current, the history table; new section "Regrading a
  cohort" with the three rake commands, the stale-only default, the
  never-lower and whole-record rules and the ±10 noise caveat; Known Gaps
  entry removed.
- `doc/Viva-History.md`: entry (Problem → Change → Outcome) citing the rev,
  this spec and the 2026-09-09 entry it closes.
- `doc/wiki/viva-authoring-guide.md`: section "After you change a briefing"
  (regrade recipe in deployment-neutral words; name every acceptable design
  first; expect noise) and a pitfalls-table row.
- `doc/wiki/instructor-viva-guide.md`: short "Re-running a grade" section
  (button, checkbox, history, Make current).
- `doc/viva-visibility.md`: the "Contest reports key on submitted_at" and
  "Closing-bell caveat" paragraphs rewritten as the rule (see above).
- `doc/backlog.md`: the grade-history entry moves to Resolved with a pointer;
  new entry "Contest page: show in-flight viva grading count".
- `CHANGELOG.md` `[Unreleased]`: Added (grade history, Make current, the
  batch tasks) and Changed (Re-run no longer destroys; failed re-runs keep
  the grade; `submissions.graded_at` follows the adopted run).

## Out of scope

- Regrading code submissions (the judge path, `evaluations`, `tasks`).
- Any change to how students start, restart or are limited.
- A student-visible grading date or history.
- Phase B of the context-policy design.

## Deviations recorded during execution (2026-09-23)

- **Make current is audited.** The spec rejected auditing single re-runs; Make current changes a student's score by hand, so it writes one `viva_grade_adopt` row on the problem (submission id, old and new run ids, old and new totals). Re-runs themselves stay unaudited: the grade row carries `requested_by_id` and `graded_at`.
- **Failed first-grading rows are non-current too.** The spec's write rule ("every run is written non-current first") is applied uniformly, so a failed first grading leaves a submission with no current row rather than a failed current row; the stuck sweeper's `where.missing(:viva_grade)` therefore matches exactly "no adopted run". Legacy rows (a failed run that is current, pre-migration) are handled by `adopt_viva_grade!`, which labels a displaced failed run `error`.
- **`record_failure!` takes `rubric_version:` from the caller** instead of computing it, so the model does not depend on the service class.
- **Known Gaps in `doc/Viva-Exam.md` had no grade-history line** to remove; the 2026-09-09 History entry was the only place the gap was recorded and the new entry closes it.
- **Grade-history table is five columns with icon-only actions** (render-check ruling during Task 4): who asked sits under the time, the rubric version under the model, Make current and Raw are icon buttons with tooltips, per CLAUDE.md "Table Action Columns"; the seven-column layout overflowed the right-hand card.
- **`viva:regrade_revert` refuses a batch whose problem no longer exists** (Task 3 review): audit rows outlive their target by design, so the revert raises a clear error instead of crashing; `viva:regrade_status` sets `Current.actor_note` like its siblings. The migration adds the composite index before dropping the old one, because MySQL 8 will not drop the only index backing the `viva_grades.submission_id` foreign key.
