# Contest-mode whitelist, contest comments, aligned detail cards — short design

Date: 2026-11-18. Three small, independent changes raised by dae in one
message. (A fourth, the Logins report opening empty, was a bug and is already
fixed in the working copy.)

## 1. Contest mode turns the IP whitelist on

**Why.** An exam should block addresses outside the exam room by default;
today the admin must remember to flip `right.whitelist_ignore` by hand.

**Change.**
- `GraderConfiguration.set_exam_mode(exam)` also sets
  `right.whitelist_ignore`: `false` in exam mode (contest, indv-contest),
  `true` otherwise (standard, analysis) — the same back-and-forth as the five
  settings it already switches (all six: exam → `'false'`, otherwise →
  `'true'`).
- `right.whitelist_ip` is never changed by the mode switch.
- **Display (dae asked for it).** The System Mode card on the contests index
  shows the IP whitelist state under the mode buttons: "IP whitelist: ON —
  allowed: 10.0.5.0/24, …" or "IP whitelist: off (pressing Contest turns it
  on) — allowed list: …". An empty list is shown as a warning ("no address is
  allowed; only admins and problem editors can get in"). A link goes to the
  configuration page. The "Mode changed" notice after a switch repeats the
  state and the allowed list.
- The single `mode_change` audit row also records the
  `right.whitelist_ignore` old/new value.
- The seed description of `right.whitelist_ignore` mentions that the mode
  switch sets it.

**Not included.** No validation or blocking on a bad list — display only. No
change to who is exempt (admins, problem editors).

**Approaches.** (a) Fold into `set_exam_mode` — chosen: one place already owns
"what an exam switches". (b) A separate "whitelist" checkbox beside the mode
buttons — more clicks, and the request was "by default". (c) Per-contest
whitelist — a different, much larger feature.

## 2. Contest comments

**Why.** After a contest there are issues to resolve and an after-action
report to keep; there is nowhere to put them.

**Change.**
- A **Comments** card on the contest manage page (`contests/show`). Each
  comment: author, time, text. Newest first.
- Stored in the existing `comments` table (`commentable` = the Contest,
  `kind: comment`, `user` = author). `Contest has_many :comments, as:
  :commentable, dependent: :destroy`. No migration.
- Text rendered with `sanitized_markdown` (staff-written text).
- Who: anyone who can open the contest manage page (admins and that contest's
  editors — `can_manage_contest`) can read, add, edit and delete. Contests
  have no report right, so there is no second tier. Students never see them.
- Works on a finalized contest — after-action notes are written then; the
  `check_finalized` gate does not apply to comment actions.
- Add/edit/delete are Turbo forms answering with the standard toast and a
  refresh of the card (the conventions in CLAUDE.md); delete asks for
  confirmation.
- Actions live in `ContestsController` (member routes), not in
  `CommentsController`, whose gates are all problem-based.

**Not included.** The unused `contests.remark` and `contests.log` columns
stay as they are (unused). No per-student comments — the student's contest
entry already has a `remark`. No audit-log rows for comments (each carries
its own author and time).

**Approaches.** (a) Comments on the existing table — chosen: dae's preferred
form, author and time for free, no migration. (b) Show the existing
`contests.remark` column as one big text box — simplest, but one blob, no
author or time, last writer overwrites. (c) Both — two places for the same
thing.

## 3. Viva Info and Submission Detail show User and Problem the same way

**Why.** The two cards describe the same things differently, and the rule for
who sees the author's name differs between them.

**Change.** One shared User row and one shared Problem row (partials), used
by both `submissions/show` and `viva_sessions/show`.
- **User row.** Shown to the owner and to staff of that problem — admin, or
  `can_edit_problem?`, or `can_report_problem?`: login + full name. Everyone
  else (another student allowed to view) sees "hidden". The login is a link
  to the user stat page for admins only (that page is admin-only; today the
  owner gets a link that bounces). A deleted user shows "(n/a)".
  This widens Submission Detail (TAs with report rights now see the name) and
  narrows Viva Info (other students no longer see the login).
- **Problem row.** The shared `problems/problem_name` block, plus the
  admin-only Edit | Stat links as today. The viva card keeps its staff-only
  statement-PDF icon (`can_view_problem_pdf?`), because the shared block hides
  its Read link on viva problems.
- **Time.** Viva "Started" also shows the exact time, like "Submitted".
- Both cards use the same label column width.

**Not included.** The rest of each card (points, status, viva start limits,
admin sections) stays as it is.

**Approaches.** (a) Shared partials for the two rows — chosen. (b) Edit the
viva card by hand to look alike — drifts apart again. (c) One card for both
pages — the remaining rows differ too much.

## Tests

- 1: mode switch sets/clears `right.whitelist_ignore` and leaves
  `right.whitelist_ip` alone; the audit row carries it; the card shows the
  list.
- 2: editor of the contest can add/edit/delete; a non-editor and a student
  cannot; works when finalized.
- 3: owner, admin, reporter see the name on both pages; a peer sees "hidden"
  on both; only admin gets the stat link.

CHANGELOG bullets for all three; `doc/Viva-History.md` entry for the Viva
Info visibility change (access policy).
