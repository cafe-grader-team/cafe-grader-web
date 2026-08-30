# Viva Context-Based Policy — Design

**Date:** 2026-07-21
**Status:** Approved in discussion (dae), pending final spec review
**Supersedes:** D1 (practice/exam mode), D2 (retakes), and D3's policy *selector*
in `2026-07-20-viva-deployment-readiness-design.md`. D3's detection/strike
*machinery*, D4-D9, and all shipped Phase-1 code outside the mode system remain
in force.

## The insight (dae, 2026-07-21)

`viva_mode` (practice/exam) was a **binary encoding of a numeric idea**: how
many times may a student start this viva, in what context? Replace the toggle
with the number, and key exam-strictness to the only context the platform can
enforce — a contest window. No per-problem mode exists to forget, flip, or
leak across the practice→exam boundary.

**Platform constraint that shaped this** (documented here because it killed
the alternative): `GraderConfiguration.contest_mode?` is **server-global** —
the whole site is in contest mode or none of it is. Long-running "wrapper
contests" for graded homework are therefore infeasible; out-of-contest
graded-ish control must come from a per-problem knob, not a contest.

## The model

**Baseline: every viva is practice.** Self-restart allowed, jailbreak alerts
logged + student notice, never auto-terminated.

**Out-of-contest limiter — per-problem daily start limit.**
- New column `problems.viva_daily_limit` (integer, nullable).
  - `nil` → fall back to `GraderConfiguration['viva.practice_daily_start_limit']`
    (existing key, default 3).
  - `N > 0` → at most N starts per student per problem per day.
  - **`0` → contest-only** *(proposed, dae to confirm)*: the problem can never
    be started outside a contest window. Restores pre-exam lockout as a plain
    visible number — no future-contest dependency (explicitly rejected as too
    much mental model).
- Admins exempt, as today.
- *Flagged limitation (accepted unless dae objects):* the unit is per-day, not
  total — `1` means one start per day until the assignment deadline, i.e.
  daily grade-improvement retries are possible. A total-attempts cap would be
  an additional nullable column later, not a redesign.

**In-contest policy — `contest_problems.viva_policy`.**
- Per-placement retake budget: `viva_retakes` (integer, nullable).
  - `nil` → contest default = **0 retakes** (single attempt — fail-safe).
  - `N` → 1 initial start + N retakes within this contest.
- Surfaced in the contest problems management table beside `enabled`.
- In-window sessions use exam-strict alert policy: warn on first strike,
  terminate on second (existing D3 machinery; only the selector changes).

**Session policy snapshot.** At `start`, resolve and freeze onto the
submission:
- `governing contest` (nullable reference): the active contest (user enrolled,
  problem included, now within window) that governs this session; `nil` =
  practice. Overlap rule: if several qualify, **strictest wins** (lowest
  retake budget).
- All later reads — alert consequences, restart permission, display, counting
  — use the snapshot, never the live problem/contest. Sessions straddling a
  window boundary keep their birth policy. (This retires the mode-flip /
  era-crossing problem permanently; the 1890 exam-era warning gate simplifies
  to snapshot-keyed logic.)

**Limiter jurisdictions are fully isolated.** Worked example (from
discussion): daily limit 5, student used 4 before the window; contest budget
3. In-window they get the full 3+1 regardless of the morning; after the
window they still have 1 daily start left (contest starts never touch the
daily counter). Rationale: exam access must never be hostage to practice
diligence (cf. the frustrated-login-burst principle), and a contest parameter
must mean the same thing for every student. Counting is by snapshot:
daily = today's starts with `governing contest = nil`; contest = starts
governed by *this* contest.

**Stale-session handling.** Starting in-window auto-archives any non-archived
session of the same problem that was started out-of-window (it is practice by
definition; archiving is what the student would ask for). Everything else
about the active-session guard is unchanged.

## Removals (Phase A)

- `problems.viva_mode` column, the form radio, the problems-index "practice
  viva" badge, the practice-in-contest guard banners (form + contest page),
  and the mode-era special-casing in the alert policy. The exam-mode notice
  in the Viva Info card becomes context text ("this session is governed by
  contest X — N retakes" / "practice — N of L starts left today").
- The 2026-07-20 spec's D1/D2 sections get a pointer note to this document.

## Explicitly rejected

- Future-contest dependency (refusing practice on problems attached to
  upcoming contests): too much hidden mental model (dae). Exam-content
  secrecy remains an availability/authoring discipline, identical to normal
  problems — documented in the wiki, not mechanized.
- Wrapper contests for graded homework: impossible while contest mode is
  server-global.
- Group-level viva policy: no current need; `viva_daily_limit` covers the
  assignment-ish cases.

## Phasing

- **Phase A (before August, mostly deletion):** drop `viva_mode` + its UI and
  guards; add `problems.viva_daily_limit` (incl. `0` = contest-only if
  confirmed) wired into the start guard and Info-card display; alert policy
  becomes log-only everywhere (correct for the practice month — NOTE: no
  terminate-capable mode exists until Phase B, accepted per calendar).
- **Phase B (pre-October hardening):** `contest_problems.viva_retakes` +
  management UI, submission snapshot columns + resolution/strictest-wins
  logic, in-window strike policy, auto-archive-on-window-entry, the
  visibility-matrix tests (design item A) rewritten against these axes, and
  the D/E documentation set.
- **Phase B MANDATORY — window-end enforcement** *(added 2026-07-21, dae:
  "they must not")*: a contest-governed session accepts NO student answers
  after its governing contest's window ends — `#answer` force-finishes
  exactly like the hard cap (system turn "(contest ended — the interview
  ends here and grading begins)", `:evaluating`, grade job on the transcript
  as it stands). Rationale: late *code* submissions self-correct (late
  `submitted_at` falls outside the report window), but a viva's
  `submitted_at` is its start — post-bell answers would improve a grade that
  counts. An assistant reply in flight at the bell completes and counts (it
  answers pre-bell input). Individual-contest mode uses the student's OWN
  window. Grading may legitimately land after the bell (ops note: pull final
  contest tables once the graders page shows no in-flight viva jobs).

## Interactions with parked items

- **A (visibility-matrix tests):** axes become archived × window ×
  contest-mode × governing-snapshot; write in Phase B.
- **D (visibility reference) + E (wiki):** write after Phase A lands, against
  this model. Publishing: upstream `cafe-grader-team` wiki is canonical; the
  mirror repo's README points there and the mirror's own wiki gets disabled.
- **Main-list all-archived display fallback** (proposed 2026-07-21, not yet
  approved): unaffected by this model; still pending dae's separate verdict.
