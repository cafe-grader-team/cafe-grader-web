# Deduction cap and spending limit — design (2026-11-21)

Status: APPROVED by dae 2026-11-21 (approach A, hint window, calls 1-7).

## Intent

Students lose points for help: a revealed hint and an AI-help request ("assist")
each reduce the problem's **full score** by their cost. Instructors very often
announce a rule like "you lose at most 30 points per problem to hints and AI
help", and today staff apply it by hand after the contest. Separately, the
system refuses AI help once a student has spent 100 points of it on one problem;
that 100 is a constant, and on 2026-11-21 a student hit it and the instructor
wanted to allow more but could not.

Two numbers, two names (used everywhere below, in the UI and in code comments):

- **Deduction cap** — the most a student's full score can drop on one problem.
  A grade rule. Students know it during the contest.
- **Spending limit** — the most points of **AI help** a student can spend on one
  problem before the system refuses more. Counts raw points, ignoring the
  deduction cap. Hints are never counted and never refused.

## The rule

For one student and one problem, with `hint` = hint points revealed and
`ai` = AI-help points charged (both raw, as stored today):

```
deduction   = cap.nil? ? hint + ai : min(hint + ai, cap)
final score = max(0, min(raw best score, 100 - deduction))
```

What `hint` and `ai` count depends on the place (confirmed by dae
2026-11-21): for a contest (Watch, contest-scoped Best Score, and the student
list in contest mode) they count only help inside **the student's own contest
window**: hints revealed in it (see "Which hints count") and AI help on
submissions made in it, which is how Watch already counts AI help. The
spending limit is separate and counts all of the student's AI help on the
problem, ever (today's behaviour; call 5).

The `max(0, …)` floor already exists in `Submission.max_score_report`; it is
missing in `Contest#score_report` today (a heavy AI user can show a negative
score on Watch) — this change applies the same formula in both, so that is
fixed too.

## Goals

1. A contest carries a deduction cap (blank = none) and a spending limit
   (blank = use the site setting).
2. The site has a spending-limit setting, default 100, editable on the System
   configuration page; it replaces the `LLM_ASSIST_FULL_SCORE` constant as the
   spend limit and can be set above or below 100.
3. Every place that shows a final score or a deduction applies the right cap;
   every place that refuses AI help applies the right spending limit.
4. Students see the cap and what they have lost so far before they spend.

## Non-goals

- Hints get no spending limit and are never refused.
- No per-problem cap or limit (one number per contest).
- Stored costs do not change: comments keep their full cost; the cap only
  changes what is counted. Changing a cap after the contest just changes the
  reports.
- The "already full score" refusal (a submission at 100 points cannot ask for
  AI help) is unchanged.
- The global Best Score page does not read caps from contests, and keeps its
  current AI counting: `Submission.max_score_report` joins AI cost by the
  best-scoring submission's id, so it charges only the AI help used on that
  submission, while Watch charges all AI help on the problem inside the
  contest. Changing it would shift every global number even with no cap set.
  Consequence, stated in the page's help: a what-if on the global page can
  differ from the contest's own report.
- The spending limit is not a ceiling: like today it stops new requests once
  spent >= limit, so a student at 95 of 100 can still make one 10-point request
  and end at 105.

## Anti-goals

- The rule must not exist in two languages. No JavaScript recomputation of
  final scores (approach B was rejected for this).
- A student must never see a number that disagrees with what staff see for the
  same contest while it runs.

## Database

- `contests.deduction_cap` — integer, nullable, no default. Valid: 0..100.
  Blank = no cap. 0 = hints and AI help never reduce the grade.
- `contests.assist_spending_limit` — integer, nullable, no default. Valid: ≥ 0.
  Blank = the site setting. 0 = no AI help in this contest (the refusal does
  not know who asks, so an admin's on-behalf request is refused too — as at
  today's 100).
- Site setting `system.llm_assist_spending_limit` (integer, value `100`),
  created by a data migration on the same pattern as
  `SeedLlmAssistCostConfiguration` / `SeedLoginThrottleExemptIpsConfiguration`
  (idempotent; leaves an existing row alone) and added to `db/seeds.rb`.
  Description: "The most points of AI help a student can spend on one problem
  before further requests are refused (hints are not counted). A contest can
  set its own."
- Both contest columns join `Contest`'s `audited only:` list; a clone copies
  both.

## Which cap and which limit apply where

| Place | Deduction cap | Spending limit |
|---|---|---|
| Watch page (`contests#view_query` → `Contest#score_report`) | that contest's | — |
| Best Score scoped to a contest (`report#max_score_query` with `contest`) | that contest's; the contest-scope card shows it ("deduction cap 30"), not editable there | — |
| Global Best Score (`report#max_score_query`, no contest) | the "Deduction cap" box in the filter form; blank = none | — |
| Student problem list (`main#list`, `main/_problem`), contest mode | the cap of the student's running contests that include the problem — if they all agree; otherwise none | — |
| Student problem list, normal mode | none | — |
| Hint-reveal and AI-help confirm boxes | as the student problem list | AI box: as the refusal |
| AI-help refusal (`Submission#llm_assist_refusal`, picker + `CommentsController#can_request_llm`) | — | contest mode: the student's running contests that include the problem — the **largest** of their limits, each blank one counting as the site setting; normal mode or no such contest: the site setting |

"Running contests of the student" = the contests `User#active_contests`
returns for the submission's **owner** (it already honours each student's own
start offset / extra time, since rev 2324). For the confirm boxes and the
refusal that is the owner of the submission, not the requester.

Why the largest limit: being refused is what makes a student complain, and the
extra cost of a few more AI calls is small. Why "no cap" when caps disagree: the
case is very unlikely (dae, 2026-11-21) and showing a guessed cap could
disagree with one contest's report; the notice explains instead.

## Which hints count (decided by dae 2026-11-21)

Today the student list counts every hint the student ever revealed for the
problem, while Watch (`Contest#score_report`, via
`Comment.hint_reveal_for_problems(problems, start..stop)`) counts only reveals
between the contest's own start and stop, so a hint revealed during a
student's extra time is free on Watch. With a cap the gap would show.

New rule, in contest mode, for both sides: a hint counts when it was revealed
inside **that student's own contest window**, `start - start_offset_second`
to `stop + extra_time_second` (the window submissions already use since rev
2324).

- `Contest#score_report`: the hint subquery filters each student's reveals by
  their own window (join `contests_users` of this contest on the reveal's
  user; `DATE_SUB/DATE_ADD ... INTERVAL ... SECOND`, never `ADDTIME`). Hints
  revealed during extra time start to count: a grade change for those
  students, in the fair direction.
- Student list (`main#prepare_list_information`) in contest mode: the hint
  query gets `comment_reveals.created_at` within `active_contests_range`, the
  same range its submissions query already uses. A hint revealed before the
  contest (e.g. in practice) stops counting there, matching Watch.
- Normal mode: the student list still counts all reveals (unchanged).
- The confirm boxes' "lost so far" uses the student-list numbers, so it follows.

## Performance (measured 2026-11-21)

The student list is the hot page during an exam. On .80 during the
2026-11-21 exam (12:00-16:00): 2,968 `GET /main/list`, peak 180 in one minute
(about 3/s), p50 44 ms (DB 14 ms), p99 189 ms, 45 queries each. On the local
copy of the .50 database (40 problems, the account with the most reveals, 282):
today's hint query 1.1 ms, the same with the window 0.8 ms (same `user_id`
index), the new per-page cap lookup 0.5 ms. Net: one more query and < 1 ms per
page. The cap lookup must stay one query per page, never one per problem.

## Student-facing text

**Problem list** (`main/_problem`), today `Full score reduced by N`:

- cap applied and it lowered the deduction:
  `Full score reduced by 30 (capped; 45 before the cap)`
- cap applies but was not reached: unchanged, `Full score reduced by 20`
- no cap applies (normal mode, or caps disagree) **and** the problem belongs to
  an enabled contest the student is enrolled in that sets a cap:
  `Full score reduced by 50 (contest grading may cap this)`
- otherwise unchanged.

The score bar uses the capped deduction when a cap applies.

**Confirm boxes** — hint reveal (`problems/_acquire_hint_confirm`) and AI help
(`comments/_acquire_llm_assist_confirm`, via `llm_assist_price_sentence`). The
existing text stays; below it, one short block:

```
Contest DS-Quiz-3 caps hint and AI deductions at 30 points per problem.
Lost on this problem so far: 25 (hints 10, AI help 15).
This hint costs 10, but only 5 more counts (25 → 30).
```

- already at or above the cap: "You have reached the cap, so this costs you
  nothing more."
- no cap applies: only the "Lost on this problem so far" line.
- AI box when the requester pays nothing (admin on behalf): unchanged text, no
  block.
- the AI box always states the spending limit:
  "AI help on this problem stops once you have spent 150 points; you have
  spent 100."

"Lost so far" uses exactly the numbers the student problem list uses
(`main#prepare_list_information`: hint cost over all of the student's reveals
for the problem; AI cost over the submissions the list counts, which in contest
mode are those inside `active_contests_range`), so the box and the list agree.

**Refusal message** (picker label and toast), today
"already spent N points on AI help for this problem": becomes
"already spent N of the M points of AI help allowed on this problem".

## Staff-facing text and UI

- **Contest edit form** (`contests/_form`): two number fields after the
  existing settings, editable by anyone who can edit the contest:
  - "Deduction cap (points per problem)" — hint: "The most hints and AI help
    together can take off one problem's full score. Blank = no cap."
  - "AI help spending limit (points per problem)" — hint: "Blank = the site
    setting (currently N)."
- **Contest show page** (`contests/show`, Contest Detail card): both values,
  "none" / "site setting (N)" when blank.
- **Score table Deduct cell** (`report/_score_table` +
  `datatables/init_score_table_controller.js`): shows the counted deduction;
  when the cap lowered it, `30 (cap)`, with the existing LLM / Hint lines under
  it showing the raw amounts. The server sends both numbers; the JS only
  formats.
- **Global Best Score filter form** (`report/max_score`): a "Deduction cap"
  number box (blank = none). Its value travels as a query parameter into the
  table's data URL (`max_score_query_report_path`), next to `contest`.

## Approaches considered

- **A — all on the server (chosen by dae).** One Ruby object holds the rule; the
  two report queries, the student list, both confirm boxes and the refusal use
  it. The global cap box reloads the table (about a second), as the filter form
  already does.
- **B — reports computed in the browser.** Instant global box, but the student
  list, confirm boxes and refusal are server-rendered, so the rule would live
  in Ruby and JavaScript and could drift; the server's `final_score` JSON would
  stay uncapped. Rejected.
- **Stored capped scores** — a cap set or changed after the contest would need
  every stored score recomputed. Rejected.

## Constraints

- MySQL 8; both report queries are SQL (`Submission.max_score_report`,
  `Contest#score_report`). The cap enters them as a bound value, never by
  string interpolation of a param.
- The global cap param comes from a form: parse as integer 0..100, anything
  else = no cap.
- Contest-mode semantics per `CLAUDE.md` "Two Operating Modes".
- Audit: the two contest columns are audited; the site setting is audited by
  `GraderConfiguration`'s own `audited`.
- Changelog `### Added` bullet; `doc/Assist-History.md` entry (the spending
  limit changes assist access policy); the System configuration description.
- No student data in tests or docs (`CLAUDE.md` standing rule).

## Left to the builder

- Where the rule lives (a small PORO, e.g. `HelpDeduction`, or methods on an
  existing model) and how the SQL fragment is built from it.
- The query that finds the running contests per problem for the student list
  and the confirm boxes (one query per page, not per problem).
- Exact wording polish of the field hints, within the meaning above.
- Test layout. Must cover: the formula (no cap / cap reached / cap not reached
  / floor at 0); Watch and contest-scoped Best Score apply the contest cap;
  global Best Score applies the box and ignores contests; the student list in
  contest mode (one contest; two contests with different problems; same
  problem, disagreeing caps → notice); normal-mode notice; both confirm boxes;
  the refusal at a contest limit below and above 100, the largest-limit rule,
  the site setting in normal mode; the data migration is idempotent; a hint
  revealed during a student's extra time counts on Watch; in contest mode a
  hint revealed before the contest does not count on the student list.

## Calls made without asking (check these)

1. Both contest fields are editable by anyone who can edit the contest, not
   admin-only.
2. Cap range 0..100; spending limit ≥ 0 with 0 meaning "no paid AI help".
3. When running contests disagree on the cap, the student list and confirm
   boxes show no cap plus the notice; for the spending limit the largest wins.
4. The contest-scoped Best Score shows the contest's cap read-only; it cannot be
   overridden there (use the global page with the box for what-ifs, keeping in
   mind its AI counting differs, see Non-goals).
5. Spending is still counted over all of the student's AI help on the problem,
   not only inside the contest window (today's behaviour).
6. The spending limit keeps today's "stop once reached" meaning, not a ceiling.
7. The global Best Score keeps charging AI help on the best submission only.
