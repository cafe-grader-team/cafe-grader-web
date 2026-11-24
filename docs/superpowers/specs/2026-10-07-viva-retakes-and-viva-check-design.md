# Viva retake rules and the contest "Viva check" page — design

**Status:** design approved in conversation 2026-10-07 (dae); this document awaits dae's review.
**Origin:** DS Quiz 2 (contest 46 `d69_q2`, 2026-10-07, viva = problem 701
`d69_v1_rule_of_three`). Proctors reported students taking the viva twice.
**Related:** `docs/superpowers/specs/2026-07-21-viva-context-policy-design.md`
(Phase B, still unbuilt), `doc/Viva-Exam.md` "Retake & Access Policy",
`doc/backlog.md` "Contest checklist" (warnings before an exam — separate work).

Terms used throughout:
- **session** — one viva attempt: one `submissions` row of a viva problem.
- **start limit** — the per-problem setting `problems.viva_daily_limit`
  ("Daily start limit" on the problem form).
- **counted session** — a session the start limit counts: started today, not a
  test-drive, at least one student answer, and (new) not covered by an
  "Allow another attempt" grant.

## 1. What happened and why it matters

- Problem 701 entered the quiz with start limit **5** (its practice-kit value).
  Any value other than 0 makes the viva behave like practice inside a contest:
  the page shows **Restart practice viva** and **End interview & get graded**,
  and a student may start up to 5 sessions. The contest score takes the best
  session, archived ones included.
- Two students finished, restarted and retook the viva (80 → 94, 74 → 83)
  before a TA lowered the limit to 1 at 09:49:59. A third restarted at 10:39
  and was refused. Quiz 1 had the same starting value (5, lowered to 1 at
  09:38); its 3 two-session students were all no-answer first sessions.
- Reading the code turned up three traps (recorded in `doc/backlog.md`):
  1. **Limit 0 means unlimited during a contest.** `VivaSessionsController#start`
     only checks contest mode for 0, never a count, and Restart is always shown.
  2. **Admin "Archive & allow retake" gives no retake under limit 1.** The
     archived session still counts toward the day.
  3. **Restart mid-interview under limit 1 locks the student out with no
     grade.** Restart archives an open session; neither the 24 h reaper nor
     Finish open vivas grades an archived session; the student cannot start
     again.
- Staff had no single place to see any of this during the exam.

## 2. Decisions (dae, 2026-10-07)

1. No hard "one attempt in a contest" rule in code. Staff must be able to give
   a second attempt (an infrastructure failure, or a deliberate choice). The
   start limit stays the control; **1 is the usual exam setting**.
2. A **per-student "Allow another attempt"** that works in contest mode,
   replacing "Archive & allow retake".
3. **Limit 0 changes meaning** to "only during contest mode, one counted
   session", so no setting allows unlimited retakes by accident.
4. **Restart is offered only when the student could start again afterwards.**
5. A **"Viva check" page** per contest, in the contest page's **Reports**
   dropdown, for live monitoring during the exam and grade checks after it,
   plus a **flag badge** on the contest page.
6. Items 5–9 of the 2026-10-07 proposals (second-opinion grading, noise runs,
   human calibration, examiner-conduct review, cheating signals) wait for the
   results of this work.

## 3. Part A — retake rules

### A1. What the start limit means

| Start limit | Outside contest mode | In contest mode |
|---|---|---|
| blank | site default (`viva.practice_daily_start_limit`, 3) counted sessions per day | same |
| N > 0 | N counted sessions per day | same |
| 0 | cannot start | **1 counted session per day** (was: unlimited) |

Admins stay exempt from the limit. Test-drives stay outside it.
"Per day" keeps today's boundary (`Time.zone.now.beginning_of_day`,
Asia/Bangkok); exams do not cross midnight. A per-contest budget remains
Phase B.

### A2. One start rule, used everywhere

Today the start guard lives inline in `#start`, the Restart button ignores it,
and the session page computes "starts left" separately. Replace them with one
method in `VivaSessionsController` (or a small `Viva::StartPolicy` PORO if the
controller grows):

```ruby
# nil when `user` may start a session of `problem` now, else the refusal text.
def start_refusal(problem, user)
```

It encodes A1 (admin exempt; 0 → contest mode required, then the effective
limit is 1; otherwise the resolved limit) against `counted_sessions_today`.
`#start` refuses with its text; `#restart` and the session page use it for A3;
the Viva Info "starts left" line reads the same numbers.

`engaged_starts_today` becomes `counted_sessions_today`: today's regular
sessions with a student answer **and `viva_retake_granted_at IS NULL`**.

**Refusal text** (student-facing):
- 0 outside contest mode — unchanged: "This viva can only be taken during a contest."
- limit reached in contest mode — new: "You have used your attempt for
  '<problem>'. If something went wrong, ask a proctor: staff can allow another
  attempt (contest page → Reports → Viva check)."
- limit reached outside contest mode — unchanged daily-practice text.

### A3. Restart

The owner's **Restart** is offered and accepted only when one of these holds:
the session is a test-drive; the session has no student answer (it never
counted); or `start_refusal` returns nil (the student has a counted start left
today, this session included in the count). Otherwise the button is hidden and
a direct POST is refused with the A2 refusal text. This removes trap 3: a
student can no longer archive their only counted session mid-interview.

The End button is unchanged (hidden for limit 0, shown otherwise).

### A4. "Allow another attempt" (staff)

**Who:** anyone who can edit the problem (`can_edit_problem`: admins and
editors of the problem's groups) — the same gate as today's archive button.
Works in contest mode.

**What it does,** under the submission's row lock, on a non-test-drive viva
session that has no grant yet:
1. sets `viva_archived_at` if not already archived — **any status**,
   including an open interview (an infrastructure failure mid-interview) or a
   session being graded (the grade still lands and still counts);
2. sets `viva_retake_granted_at` and `viva_retake_granted_by_id`, so the
   session stops counting toward the start limit — the student can start
   exactly one more;
3. writes one `AuditLog.record!(auditable: problem, action: 'viva_retake_grant',
   object_changes: {'submission_id' => [nil, id], 'user' => [nil, login]})`,
   with a badge in `AuditLogsHelper#audit_action_badge`.

An open session archived this way is **not** graded (staff chose to replace
it). The student's best session still counts in scores, as today.

A grant also works on an **already archived** session (the 10:39 Quiz 2 case:
a student who restarted and is now refused). It is idempotent: a second click
on a granted session changes nothing and says so.

**Where the button is:**
- on the session page's **Admin** card, replacing "Archive & allow retake";
- on each student row of the **Viva check** page (B4), where it grants on that
  student's latest counted session of that problem.

Both are `button_to` with a `turbo-confirm` naming the student, answered with
a toast (Flavor A). The session page's Viva Info card shows "Another attempt
allowed by <login>, <time> ago — this session does not count toward the start
limit."

**Data:** two nullable columns on `submissions`:
`viva_retake_granted_at` (datetime(6)) and `viva_retake_granted_by_id`
(integer). Adding nullable columns is an INSTANT operation on MySQL 8.0;
measure it on the local prod copy before release (`submissions` is 6 GB on
cp-grader).

**Route:** `POST /submissions/:id/allow_viva_retake`
(`SubmissionsController#allow_viva_retake`); the old `archive_viva` route and
action are removed.

## 4. Part B — the Viva check page

### B1. Place, access, refresh

- `GET /contests/:id/viva_check` (`ContestsController#viva_check`, in
  `EDITOR_ACTION`, so `can_manage_contest` applies — same access as AI Usage).
- Linked from the contest page's **Reports** dropdown, after User Activity.
- While the contest is running (`Contest#contest_status == :during`) the
  report body sits in a turbo frame that the existing `refresh` Stimulus
  controller reloads every 30 s; otherwise it is static.
- Built by a read-only PORO `VivaCheckReport` (beside `AiUsageReport`).

### B2. Scope

Sessions = `Contest#submissions` (regular — no test-drives, no near-miss
shadows; per-user offset and extra time respected) on the contest's viva
problems. Several viva problems are reported in separate sections.

### B3. Flags

Each flag is shown as a badge in the student row with a tooltip. **Needs
action** flags count toward the contest-page badge; **worth a look** flags do
not.

| Flag (UI text) | Rule | Level |
|---|---|---|
| Retook | the student has 2+ answered sessions without a grant | needs action |
| Waiting for reply | an assistant turn has been `processing` for 60 s or more | needs action |
| Reply failed | the latest assistant turn is `error` | needs action |
| Grading failed | status `grader_error`, or `evaluating` with no current grade for 5+ minutes | needs action |
| Left unfinished | archived while `submitted`, has answers, no grant (should not happen after A3) | needs action |
| Grade doesn't add up | a rubric item above its maximum, items not summing to the total (±0.01), or rubric names that don't match the problem's rubric | needs action |
| Rubric unreadable | (problem-level) the briefing's `# Rubric` cannot be parsed, or its weights don't sum to 100 | needs action |
| No answer yet | open, no student answer, opened 5+ minutes ago | worth a look |
| Short but high | 3 or fewer answers and 50+ points | worth a look |
| Ended early | the student pressed End (`(student ended the interview` system turn) | worth a look |
| Rule-break flag | a turn has `alerted = true` | worth a look |

Thresholds are constants on `VivaCheckReport`.

**Rubric parsing** — new `Viva::Rubric.parse(viva_prompt)` (in
`app/services/viva/`): takes the `# Rubric` section (to the next heading of the
same or higher level), reads lines `- key (weight): …` (key optionally in
backticks, weight an integer or decimal), returns `{weights: {key => n},
readable: bool}`. The contest checklist (backlog) reuses it later. Grade values
in `viva_grades.score_json` are numbers; a hash value with a `score` or
`points` field is read as that number; anything else counts as "doesn't add
up".

Measured on the local prod copy (2026-10-07): across all 703 current grades,
2 had an item above its maximum and 3 did not sum to the total; problems 670
and 671 have unreadable rubrics; Quiz 2 would show 2 "Retook", 3 "Short but
high", 9 "Ended early" and 5 "No answer yet".

### B4. Layout

1. Title row like AI Usage (contest name, "Viva check" pill, Manage / Watch
   buttons) and the window line.
2. **Tiles:** sessions opened (students of enrolled); answered at least once;
   open now; graded / grading / failed; opening-question wait p95 and max
   (seconds; same measure as AI Usage); needs action (count).
3. Per viva problem: a **students table**, flagged rows first, then by login —
   Student (login + name) · Sessions (total, answered) · Latest session
   (status, answers, score — links to the session page) · Best score · Flags ·
   Action ("Allow another attempt" when the student has a counted session
   and the viewer can edit that problem — page access alone is not enough).
   Plain HTML table (no DataTable), so the 30 s turbo-frame refresh stays
   simple; ~175 rows.
4. A one-line legend of the flags.

### B5. Contest page badge

Next to the viva grading status on `contests/show`, a badge "N to check"
(needs-action count) linking to the Viva check page; hidden when zero. It
lives in the `_viva_status` partial so it refreshes with it.

## 5. Docs, changelog, history (same commits as the code)

- `doc/Viva-Exam.md`: "Retake & Access Policy" (A1–A4), Lifecycle step 1,
  "Admin actions on the viva session page", Known Gaps.
- `doc/Viva-History.md`: entry for the retake rules and the Viva check page
  (problem observed → change → outcome).
- `doc/wiki/viva-authoring-guide.md`: exam setting (start limit 1, or 0 for
  contest-only) and the pitfalls row "practice kit used for an exam".
- `app/views/problems/_viva_fields.html.haml`: the start limit hint matches A1.
- `CHANGELOG.md` `[Unreleased]`: Added (Viva check, Allow another attempt),
  Changed (limit 0, Restart), upgrade note (two nullable columns).
- `doc/backlog.md`: the three traps in "Contest checklist" are marked fixed,
  citing the implementing revs; the checklist itself stays open.

## 6. Testing

- `Viva::Rubric`: the 701 briefing, backticked keys, decimals, no section,
  weights ≠ 100.
- `VivaCheckReport`: one fixture contest exercising every flag, the scope
  (test-drive and out-of-window sessions excluded), the needs-action count.
- `VivaSessionsController`: limit 0 in contest mode allows one counted
  session then refuses with the proctor text; a no-answer session does not
  count; Restart hidden and refused when no start is left, allowed with no
  answers or a start left; a granted session stops counting.
- `SubmissionsController#allow_viva_retake`: open, done and archived
  sessions; idempotent second click; editor allowed, student refused; audit
  row written; test-drive refused.
- `ContestsController#viva_check`: access (editor of the contest yes,
  student no), the Reports dropdown link, the badge.
- One headless screenshot pass of the session page, the Viva check page and
  the contest page before review.

## 7. Out of scope

- The contest checklist (backlog entry; dae elaborates later).
- Proposals 5–9 (second-opinion grading and the rest).
- Phase B: per-contest retake budget, governing-contest snapshot,
  window-end force-finish.
- Grading a session voided by "Allow another attempt".

## 8. Rollout

1. `bin/rails db:migrate` (two nullable columns on `submissions`).
2. On cp-grader, set exam vivas to start limit 1 (or 0) before each quiz;
   until the contest checklist exists, this is a manual step.
3. Separately (master 2232): put the exam gateway addresses in
   `right.login_throttle_exempt_ips`.
