# Backlog

Design refactors, deferred decisions, and "someday" follow-ups that don't yet
warrant a GitHub issue or fit in a single TODO comment. Each entry should be
short — title, why it matters, current state, proposed direction, rough size.
Trim or move to an issue when you start the work.

Conventions:
- One section per entry. Keep them grep-able.
- Cite file paths so the next reader (or Claude) can jump in cold.
- Don't put per-commit TODOs here — those go inline as `# TODO(scope): …`.
- Don't put scheduled or assigned work here — that goes on GitHub.
- When an entry is resolved, cut it to a pointer block (what shipped, rev, where
  the durable record lives, any residual) and move it to the `## Resolved` ledger
  at the bottom, newest first. The full write-up stays in `hg log`, the CHANGELOG
  and the linked docs.
- An entry we have decided NOT to do until something specific happens goes under
  `## Waiting for a signal`, with an explicit **Reopen when:** line. That is a
  different state from low priority: the work is understood and often designed,
  but there is no evidence or requirement yet that it is wanted. Don't start one
  without its signal; do move it back up the moment the signal appears.

---

## Languages that still do not grade (found by `engine:langcheck`, 2026-11-14)

**Why it matters:** each of these is offered in the language picker wherever
a problem permits all languages, and a student who picks one gets a
compilation or grader error that is not their fault. Counts are from the
cp-grader database copy of 2026-10-28.

- **Java — fixed in code (rev 2278), not yet on the hosts.** Each judge host
  needs `bin/rails engine:detect WRITE=1` + grader restart. The 53 submissions
  that failed with `Error loading java.security file` (2025-08-20 →
  2026-10-05) are not regraded; decide whether to rejudge them
  (`Submission#add_judge_job(live_dataset, -10)`).
- **Pascal — fixed in code (revs 2278 + 2279), not yet on the hosts.** Two
  faults: the wrong config key, then fpc not finding its units without
  `/etc/fpc.cfg`. The same `bin/rails engine:detect WRITE=1` writes the
  `compiler_options: pas:` line. Of its 75 submissions only 40 look like
  Pascal (24 contain `#include`), so hiding it from the picker is still worth
  considering where no course uses it.
- **PHP (170, never passed).** Only the missing `compiler: php:` line; the
  built-in program passes once the path is set. Per-host `worker.yml` edit.
- **Octave (4,209, never passed).** `Compiler.get_compiler` has no branch for
  it: "Unsupported language (octave)". Either write the compiler class or
  remove the `Language` row.
- **Haskell on this dev machine only:** compiles, then the run dies with
  `Ticker: Failed to spawn thread` — the built-in Haskell options have no
  `-p`, and the GHC here needs a second thread. cp-grader graded Haskell on
  2026-10-10, so check with `engine:langcheck ONLY=haskell` on a real host
  before changing anything.

**Proposed direction:** fix or hide each one; a language that cannot grade on
a host should not be selectable there. **Size:** PHP is a config line per
host; Octave is a product decision first.

---

## Contest reports — what a contest should report after the exam (direction not chosen)

**Raised 2026-09-12 and 2026-09-22, never designed** — each time a nearby
item was taken instead (the AI Usage page, then Finish open vivas, test-drives,
grade history). Recorded 2026-09-25 so the next attempt starts here; direction
1 shipped 2026-09-30, directions 2 and 3 remain open.

**What a contest has today:** Watch (`contests#view`: best score per student
per problem, final score after assist and hint cost, chart); AI Usage
(`contests#ai_usage`, fixed and extended rev 2207); the per-student contest
stat page (`user_admin#stat_contest`). The Report menu pages (Max score,
Submission, Activity, AI, Cheat; `ReportController#selected_users` /
`#selected_problems` / `#submission_in_range`) cannot take a contest as the
scope: users come from groups, problems from ids/groups/tags, time from a
date range, so per-student offset and extra time are lost.

**Candidate directions (dae to pick):**
1. ~~**"This contest" as a scope on the Report pages**~~ — DONE rev 2209
   (2026-09-30): `?contest=ID` on Best Score / Submissions / User Activity,
   picker in the title row, **Reports** menu on the contest page; the AI
   report stays range-based and points at the contest's AI Usage page.
2. **A post-exam results page** — per-problem statistics (mean, spread,
   pass counts), viva grade beside code score, who submitted nothing, a
   gradebook export. New page; needs a short spec.
3. **Combining two contests** — e.g. the Quiz 1 remedy (Quiz 1 viva =
   max(Q1, Q2 viva) for everyone who opened the Q1 viva, decided
   2026-09-25, `doc/exam-postmortem-2026-09-09-d69_q1.md`). Until built,
   the per-student max table is pulled by hand.

**Also open:** the AI-time columns (rev 2207) have no real data locally —
the local prod copy ends 2026-09-12, before the timing deploy (chula_cp 2158,
verified on cp-grader 2026-09-21). Check them against the first contest with
AI use held after that.

---

## Contest checklist — warnings before an exam starts (direction agreed, details to come)

**Raised 2026-10-07 by dae after DS Quiz 2; dae will elaborate the item list.**
A checklist on the contest page that lists what looks wrong for an exam. It
**warns, never blocks** — staff may have a reason.

**Why:** both DS quizzes started with the viva set up for practice. Quiz 1
(contest 43, problem 705) and Quiz 2 (contest 46, problem 701) each began
with the viva's start limit (`problems.viva_daily_limit`) at 5, and each was
lowered to 1 by hand mid-exam (09-09 09:38, 10-07 09:49). In Quiz 2 two
students finished, restarted and retook the viva before the change (80 → 94,
74 → 83; the contest score is the best session, archived ones included).
The viva also said "practice viva" in 147 of 148 greetings because the
scenario text (`problems.description`) still carried the practice-kit line.

**Decided 2026-10-07 (dae): no hard single-attempt rule in code.** Staff may
want a second attempt, or need one after an infrastructure failure. The
per-problem start limit stays the control, and the checklist warns about it.

**Items known so far:**
- Viva problems: start limit (see the three facts below); "practice"
  wording in the scenario or briefing, or a `-practice` conduct tag;
  rubric not machine-readable or not summing to 100; no staff test-drive
  since the problem was last edited.
- All problems: enabled (problem available, contest problem enabled), AI
  assist allowed or not as intended (`contests_problems.allow_llm`), proper
  structure (live dataset with testcases, statement, permitted languages,
  manager files for `with_managers`).
- Contest: users enrolled, site in contest mode, start and stop times.
- Login: CU-net password login on (`chula.allow_cu_net_password`). In Quiz 2
  it was switched off 09:01–09:05, students' correct CU-net passwords failed,
  and the failures locked the whole room out of login (all students share
  the exam gateway's IP address, which the login lock counts per address).

**Three start-limit traps found 2026-10-07 — all FIXED** (master 2238–2240,
`Viva::StartPolicy`, `doc/Viva-Exam.md` "The start limit"): limit 0 used to
mean unlimited retakes during a contest (now one counted session); admin
"Archive & allow retake" gave no retake under limit 1 (replaced by **Allow
another attempt**, which stops the session counting); Restart mid-interview
under limit 1 locked the student out ungraded (Restart is now offered only
when a new start is possible). What the checklist still has to warn about is
a start limit other than 1 or 0 on a contest's viva.

**Items added by the 2026-10-18 exam-viva audit** (dae 2026-10-18: keep in the backlog; course-prep
`data-structures/viva/exam-audit-2026-10-18/report.html`; the human half of
the same list is the authoring guide's §8b gate):
- Viva problems with no **exam** overlay attached (neither quiz had one), or
  with the `-practice` overlay still attached.
- Scenario text containing a term the briefing says must not appear — needs
  a small convention, e.g. a `# Not in the scenario` list in the briefing
  (the Rule of Three subtitle named the answer to its last criterion).
- Interview-plan rungs with more than one question mark (bundled rungs were
  the main cause of a zero criterion); a criterion whose only rung is last.
- The grading model configured for the exam differs from the one chosen in
  "Exam viva grading" below.

**Reuse:** `Viva::Rubric.parse` (rubric readable, weights sum to 100) and the
contest's Viva check page (`VivaCheckReport`) already exist; the checklist's
viva rows can call the same code.

**Size:** small to medium — a PORO of checks plus a card on `contests/show`.

---

## Exam viva grading — the AI grade runs 14–18 points high (direction not chosen)

**Found 2026-10-18** (full audit of both DS exam vivas, 286 sessions;
`doc/Viva-History.md` 2026-10-18). gemini-3.7-flash grades above an
independent reading in every score band and never below, while ranking
students correctly. It ignores the conduct's grading conventions (hint
discount, examiner-supplied content, unreached = 0). Already suspected in the
2026-09-01 Buggy Counter audit (a third over-graded; "grading default to
3.1-pro or Sonnet" left open) and in the 2026-09-12 Opus pilot (11 points
stricter on 30 sessions). Not fixed before either exam.

**Candidate directions:** (1) conventions repeated as caps inside each
criterion (authoring guide §4c — prompt-only, try first); (2) a stronger
grading model for exams; (3) two grading passes, keep the mean. Test any of
them against the audit's own independent grades: the 286 transcripts and
per-criterion scores are in `findings/batch-NN.jsonl`, so a candidate grader
can be scored offline before an exam (university quota only).

**Size:** small for (1); (2)/(3) are config plus one offline evaluation run.

**State:** dae 2026-10-18 — backlog, not scheduled.

**Quiz 3 (2026-10-21, problem 721, contest 47) — the narratives too.** The
exam overlay says a narrative names only the topic, yet 65 of 109 Quiz 3
narratives name `mLess`, 51 describe the re-check bug the student was
supposed to find, and 11 name a fix (course-prep
`data-structures/viva/quiz-2569-3-postexam-2026-10-28/report.html` §3). A
candidate grader should be scored on narrative leaks as well as points. The
gap on Quiz 3, from a blind 30-session sample: AI +9.8 on average, never
lower, ranked almost the same (0.95), and larger for higher grades (+5 in
the bottom third, +14 in the top) — mostly credit for examples that are not
valid heaps and for untraced claims (`regrade-sample/` in the same folder).

**2026-10-29 — direction (2) taken: grading moved to gemini-4-argon** (chula_cp
2273; `doc/gateway-model-test-2026-10-29.md`). Scored offline on the 316
sessions with reader grades: +5.6 points above the readers against +14.5 for
3.7-flash (Q1 +2.7, Q2 +9.0, Q3 +3.0); on Quiz 3 its narratives name `mLess`
in 4 of 30 sessions against 22. Still open: Quiz 2 (Rule of Three) is 9
points high; check the first exam graded by argon against a blind sample
(authoring guide §9) before closing this item. Direction (1) is still worth
doing for any model.

---

## Viva replies on gemini-4-argon — two checks before switching

The 2026-10-29 model test (`doc/gateway-model-test-2026-10-29.md`) kept
`viva_turn` on gemini-3.7-flash although argon did better on the audit faults.
Before moving the examiner replies to argon:
1. **Simultaneous load at exam hours.** 30 replies sent at once, run twice at
   night, gave argon a slowest reply of 37 s, then 9 s. Repeat during exam-hour
   traffic (around 10:00) with
   `course-prep/gateway-argon-2026-10-29/step3_turns.rb burst`.
2. **Altered scenario code.** One argon opening in 13 with code inserted a
   made-up line into the scenario's class (problem 701). Either accept it and
   watch, or show the scenario from the platform so the model never has to
   copy it (code change: render `problem.description` above the first turn and
   tell the examiner not to repeat it).
Also known: argon narrows the search more often (13 of 40 replies against
5–7) and bundles questions; its opening takes about 20 s.

---

## Viva rule-break notice says "practice mode" during exams

`Llm::VivaTurnAssist#apply_alert_policy` always takes the practice branch
(`exam_policy?` is `false` until Phase B), so a flagged turn in an exam shows
the student "In practice mode the interview continues; flags are logged for
instructor review." Seen twice in DS Quiz 3 (contest 47, 2026-10-21). The
behaviour (log, continue) is intended until Phase B; only the wording is
wrong. Fix: a mode-neutral sentence ("The interview continues; flags are
logged for instructor review."), or choose the wording from the problem's
conduct overlay. Small.

---

## Viva misreadings — three cases the conduct and grading rules do not yet separate (policy decided 2026-11-06)

dae's policy (2026-11-06, while preparing the AI Gateway showcase talk), for a
student answer that is not an answer to the question asked:

1. **Honest misreading** — the examiner's words can honestly be read the way the
   student read them. The examiner explains and rephrases; **no penalty**.
2. **Part left unanswered** — the examiner's message held two or more questions
   and the student answered some. The examiner restates the rest **word for
   word**; **no penalty** (students answer a chat in pieces).
3. **Careless misreading** — the words were clear (e.g. "A *and* B") and the
   student answered another question. Costs credit **only on a reading /
   understanding criterion** if the rubric has one; otherwise nothing.

Test for 1 vs 3: would a careful reader of the examiner's exact words reach the
student's reading? The grader can apply it from the transcript, so the examiner
need not judge in the moment; it rephrases or restates in every case.

Today: the exam overlay allows one restatement and folds "narrow to a smaller
instance" into it; the base conduct's "off-topic answer: redirect once, then
move on" likely makes a misread question look off-topic; the grading convention
discounts an answer that came "after the examiner's hint" and may count a
clarification as a hint. Nothing restates the unanswered half of a bundled
question.

Also: every clarification costs a **turn** even when it costs no points. The
guide's soft cap (rungs + 2) leaves two spare turns for all hints,
clarifications and re-asks together; Buggy Counter (693, Sept audit) had 25%
of completed sessions at the 12-turn hard cap, and of 16 students who scored 0
on "state the bug" only 2 earned anything on the next, independent rung.

Evidence from the exam transcripts (course-prep `viva-talk-2026-11-06/viva-learning-analysis-2026-11-06.md`,
H3): honest misreadings are rare (7 in 394 exam vivas); the big loss is case 2
— in 191 of 394 the examiner moved on without the unanswered part (restated it
only 166 of 524 times). Exams hardly reach the turn cap (3 of 394), so there the
cost is lost evidence, not turns; the turn-budget point matters for practice.

Direction: (a) base conduct — the three cases and the examiner's move for each;
(b) grading conventions — no discount for a clarification or a restatement;
(c) authoring guide — size the turn budget with slack, list expected
misreadings per rung with the clarifying sentence, one question per message;
(d) parked: clarification turns not counting toward the cap needs the examiner
to mark them, which cannot be relied on today. Size: (a)–(c) small prompt +
doc work, then a regrade check on one problem; touches `doc/Viva-History.md`
and the guide in the same commit.

---

## Memory accounting for C/C++ — address space vs cgroup (POLICY + a real bug)

**Raised 2026-08-03 from the CMS migration validation.** Three separate things
are tangled here; separating them makes the decision much easier.

### The mechanics (verified on both sides)

Both graders run isolate. Cafe passes `-m <KB>` for C/C++ → **RLIMIT_AS**, which
caps *address space*: everything the process maps, including memory reserved and
never touched. CMS passes `--cg-mem` → **cgroup accounting**, which caps pages
actually faulted in (RSS).

Concretely: a global `int dp[5000][5000]` is 100 MB of address space the instant
the binary maps its BSS, so cafe kills it at startup even if the solution touches
2 MB. Under cgroups the untouched pages cost ~nothing and it runs. Cafe fails on
*declaration*; CMS fails on *use*.

Cafe already uses cgroups for java/digital/go/python
(`app/engine/judge_base.rb#isolate_need_cg_by_lang`) — C/C++ are the exception.
isolate supports **both** flags simultaneously (`-m` and `--cg-mem` are separate
options), which enables the hybrid below.

### Issue 1 — POLICY: should unused declared memory count? (legitimate either way)

**Cafe style (address space) — for:**
- Deterministic: the verdict never depends on which testcase or how much of the
  array gets touched. Same program, same verdict, every run.
- Teaches memory discipline explicitly: "your solution must FIT in 256 MB" is a
  real competitive-programming skill, and declaring `MAXN` far beyond the limit
  is caught immediately rather than tolerated.
- Prevents lucky passes: a solution declaring 1 GB but touching little passes the
  given tests under cgroups, then dies on data that touches more. Address-space
  limiting rejects it consistently.
- Fails fast (cheaper to grade).

**Cafe style — against:**
- Counts things the student does not control: the static binary's mappings,
  allocator arenas, thread stacks, libstdc++'s own reservations. A solution
  genuinely using 50 MB can show substantially more address space.
- Penalises a widely-taught idiom (declare `dp[MAXN][MAXN]`, use a submatrix).
- Diverges from IOI / CMS / Codeforces, where limits are RSS-based. Students
  trained elsewhere — and problems authored elsewhere — assume the other model.
- Linux over-commits by default, so reserved-but-untouched memory costs the
  machine nothing; the limit measures something that is not a real resource cost.

**cgroup style — for:** measures what the machine actually pays; matches the
convention every imported problem was authored against; enables correct MLE
reporting (see Issue 2). **Against:** allows declare-huge-touch-little
solutions to pass; verdict can vary by testcase; may count page cache for files
the sandbox reads (needs testing on large-input tasks).

### Issue 2 — A BUG, independent of the policy choice

```
Evaluation.count                          6,922,221
Evaluation.where(result: :memory_limit)           0     <-- never, not once
Evaluation.where(result: :crash)            555,119     (8.0%)
```

**Cafe has never once reported "memory limit exceeded" for C/C++.** Under
`RLIMIT_AS`, an over-limit allocation makes `malloc` return NULL or throw
`bad_alloc`; the process dies by signal and isolate reports a runtime error, so
cafe records `crash` (`x`). Students exceeding memory are told their program
crashed — indistinguishable from a segfault. isolate can only report a genuine
memory-limit kill through cgroup accounting (`cg-oom-killed`), so **accurate MLE
verdicts require cgroups regardless of which policy is chosen for the limit.**

### Issue 3 — Imported CMS problems are effectively stricter than authored

Their `memory_limit` values were calibrated against RSS semantics. Enforced as
address space, the same number is a tighter budget, so students lose points they
earned on the source instance. Measured in the migration sweep: submissions CMS
scored 100 scored **0** here; enabling cgroups took two affected tasks from 8-9/10
to **10/10 exact** (`doc/CMS-Migration.md` §5.1).

### Measured behaviour (isolate experiments, 2026-08-03)

**How RSS/cgroup accounting actually charges.** A program declaring a 1 GiB
global array, touching the first 64 MiB, then the last 64 MiB, leaving the
middle untouched:

| point | RSS |
|---|---|
| declared, nothing touched | 1.6 MB |
| after touching FIRST 64 MiB | 67 MB |
| after touching LAST 64 MiB | **133 MB** |

So cgroup accounting charges the **sum of every distinct page ever touched** —
not the maximum of the regions, not the whole array. Untouched pages are never
charged; once an anonymous page is faulted in it stays charged (a judge box has
no swap, so nothing is reclaimed). Granularity is one page: touching a single
byte charges 4 KB. Note transparent hugepages are `madvise` on this host; under
`always`, a single byte could charge a 2 MB huge page and inflate sparse
patterns considerably.

**What `-m` and `--cg-mem` do together.** They are independent limits and both
are enforced — whichever binds first wins. Measured with a 128 MiB limit and a
program declaring 256 MiB:

| flags | declares 256 MiB, touches 0 | declares 256 MiB, touches 200 MiB |
|---|---|---|
| `-m` only (today) | killed, **signal 11**, `max-rss: 816 KB` | killed at startup, same |
| `--cg-mem` only | **runs fine** | killed, **signal 9**, `cg-mem` exactly at limit |
| both, equal | killed, **signal 11** (AS binds first) | killed at startup |
| `--cg-mem` limit + generous `-m` (1 G) | **runs fine** | killed, **signal 9** at exactly the limit |

**The decisive detail: signal 11 vs signal 9.** An address-space kill reports
SIGSEGV with `max-rss` of a few hundred KB — the process died having used almost
no memory, because the kernel refused the mapping, and *nothing in isolate's meta
indicates memory was the cause*. That is precisely why this repo has 555,119
`crash` verdicts and zero `memory_limit` ones. A cgroup kill reports SIGKILL with
`cg-mem` sitting exactly at the limit — unambiguous, and mappable to a proper `M`
verdict.

**Consequence for the policy debate:** "declaring `dp[5000][5000]` beyond the
limit should show MLE" is **not achievable through `-m`**. Address-space
enforcement can fail the program but can only ever report it as a crash. Wanting
both fail-on-declaration *and* an honest MLE verdict means `-m` cannot supply the
second half.

### Options

1. **Keep `-m` alone (status quo).** Your policy, but over-declaration keeps
   reading as "crash" and imported problems stay stricter than authored.
2. **Both flags, equal limits.** Byte-for-byte the same declaration behaviour as
   today, but a program that stays within address space and then over-uses gets a
   clean MLE. Strictly better reporting, zero loosening — the conservative fix.
3. **`--cg-mem` at the limit, `-m` generous (e.g. 4x).** Real memory overuse gets
   an accurate verdict; absurd declarations still fail fast; the common idiom
   (declare `MAXN`, use a submatrix) passes as it does on CMS/IOI/Codeforces.

Older framing kept below for reference:

1. **Keep cafe policy, fix the verdict.** Run with cgroups for accounting/reporting
   but keep an address-space cap too (`--cg-mem=<limit>` *and* `-m=<limit>`):
   students get a correct MLE verdict, and declaring beyond the limit still fails.
   Closest to today's behaviour while fixing Issue 2.
2. **Adopt CMS semantics** (`--cg-mem` only): full fidelity for imported problems,
   matches IOI convention. Strictly more permissive, so no existing grade can fall.
3. **Hybrid, per origin:** CMS semantics for imported problems, cafe semantics for
   native ones. Most faithful, but two grading models to explain and maintain —
   probably not worth it.
4. **Do nothing**, and raise imported problems' memory limits to compensate.

### Rollout requirement whichever is chosen

Use the existing Mode A replay harness (`problems:replay_validate`) to re-grade a
sample of **existing, non-imported** problems before/after and diff against stored
grades. Expect only `x -> P` transitions; **any `P -> x` means the page-cache
effect is real and stops the rollout.** Include tasks with large inputs. ~1 hour
of machine time; converts "should be safe" into "measured".

**Size:** the code change is one line (plus one more for the hybrid). The
decision and the verification are the work.

---

## Submission assist (Codey) — what is still open after the 2026-09-03 review

**Context.** Code review + prod-copy data pass over `Llm::CommentAssist` /
`CommentsController#llm_assist` on 2026-09-03; the deliverables (master
2084–2113, prompt `codey-core` v2.2 = `course-prep` rev 13) went live on
2026-09-05 — timeline in `doc/Assist-History.md`, study in
`doc/assist-corpus-eval-2026-09-03.md`. Follow-ups closed 2026-09-09: an
admin's request is free for the student (2116); per-model requests / points /
dollars / tokens on the user and problem stat pages (2117); Genie models off
the picker by default, relay kept as a backup (chula_cp 2118, config);
`codey-thai` kept as is (decided). All of it live on production 2026-09-10 15:51
(chula_cp 2123); the same day dae ran the clean-up script — 397 stuck
`processing` rows marked failed, token counts backfilled on 5,184 answers,
the dead `AI_viva` tag deleted. Still open:

### Measurement (after a term of the new payload + prompt)
- **Effectiveness re-measure**: assisted improved 36% / same 50% / reached 100
  18% before 2089, paired figure 27% → 38% (never quote the never-asked
  baseline). Re-run `frame.rb` / `frame2.rb` / `frame3.rb` (archived in
  `~/cafe-grader/assist-eval-2026-09-03/`, copies in `course-prep`) and compare
  read scores and outcomes against the 2026-09-03 document — compile-error and
  repeat-request cells first.
- **Gateway models: read done 2026-10-13; picker decided 2026-10-29 (Opus out,
  gemini-4-argon in, chula_cp 2273 — `doc/Assist-History.md` 2026-10-29).** Opus
  misdiagnoses 8–12 of 60 answers, flash 0 of 39; Opus keeps to one issue in
  48% vs flash's 82%; outcomes do not differ
  (`doc/assist-gateway-read-2026-10-13.md`). With thinking on (tested
  2026-10-15), Opus drops to 5 of 60 wrong. On the Quiz 2 head-to-head (same
  60 inputs) the wrong-diagnosis rates are flash 3%, Opus 37% and thinking
  Opus 12%; thinking Opus takes 51 s per answer. The study recommended taking
  Opus out of the picker and keeping it as a backup. **DECIDED 2026-10-28
  (dae, after DS Quiz 3): keep both in the picker as they are.** In Quiz 3
  Opus took 299 of 362 requests (83%) and USD 35.41 of 36.23
  (`doc/Assist-History.md` 2026-10-28). *SUPERSEDED 2026-10-29:* on the same
  60 inputs gemini-4-argon was 3% wrong at USD 0.025 per answer; dae replaced
  Opus with it in the picker, Opus kept as a backup. Open: argon keeps to one
  issue in 62% (flash 73%) — check in the next read; measure its wait in the
  next quiz from `comments.llm_latency_ms`. The Gateway now also serves
  gemini-3.1-pro-preview (seen 2026-10-29), the 0/90 model the v2.2 prompt was
  tested on — a candidate if argon disappoints.

### Scoring
- **Requests made after the contest count against the contest score.**
  `Contest#score_report` joins every assist comment on the contest's
  submissions, whatever its `created_at`, into `final_score = LEAST(max,
  100 − llm − hints)`. In DS Quiz 3 (contest 47) two students asked for help
  on their quiz submissions after the quiz (2026-10-21 13:48, 2026-10-26
  03:30) and were charged 10 quiz points each; no score changed only because
  both were below the cap. Fix: count only comments created inside the
  student's contest window (the same start offset / extra time as
  `Contest#submissions`), with a regression test. Small.

### Prompt
- **TLE hand-over shape fix** (template or a second pass): the model names the
  allowed tool, then lays out the redesign anyway (6–7 of 18). The
  "name the tool then stop" rule made it worse (7 → 9/18, 2026-09-05) and was
  reverted; parked for a shape-level change plus a blind check.

**Size:** the prod steps are minutes; the Gateway read is a session; the TLE
fix is prompt authoring plus a blind check.

---

## Import/Export & CMS interop (from doc/problem-import-export-design-2026-07-14.md)

**Status 2026-08-02.** A *live-server* CMS import path shipped (master revs 1960–1968;
spec `docs/superpowers/specs/2026-08-02-cms-clone-import-design.md`):
`rails "cms:clone[task]"` ssh's to the CMS host, wraps the official `cmsDumpExporter`,
filters one task's subtree, fetches its blobs via `FileCacher`, and converts through
`Converters::CmsDumpConverter` into the trusted `ProblemImporter`. Validated against
c2 (`mar2025_eatingfish`): structure exact, and a replay of 8 real c2 submissions
scored 8/8 identical to CMS (only benign `T→P`/`x→P` per-testcase diffs). None of the
capability items below are closed by that work — Communication / OutputOnly / file-I/O
/ GroupMinPrereq are now *detected and rejected with a clear message* pointing here,
which is the interim behavior the 2026-07-14 design specified.

**Production transport that works today** (verified 2026-08-02, no new code needed):
clone on a box that has ssh to the CMS host → problem page **Download (all datasets)** →
upload that zip on the production server's existing **Problems → Import** page. Export→
import was round-tripped on the cloned problem: every field identical (both datasets,
42 testcases, weights, managers, statement, testcase bytes). This keeps production from
ever needing ssh/sudo access to the CMS host. Known cosmetic gap: the **live** dataset's
name is not preserved through a plain zip import (root `ds_name` is inert — the importer
auto-names the live dataset `Dataset N`; additional datasets keep their names). `cms:clone`
renames it explicitly; the web import path does not.

**Open, in the order that serves "import c2 → production, repeatably":**

- **UI-facing CMS *package* import (unbuilt).** The 2026-07-14 design's UI decision —
  "existing import page with format auto-detect" — is still unimplemented. Note the
  shape difference: `CmsDumpConverter` consumes a *dump bundle* produced by our own
  extractor, NOT a CMS-native package, so the upload path needs the originally-planned
  `CmsItalianConverter` (`task.yaml`) and/or `TpsConverter` (`problem.json`) plus
  sniffing in `problems_controller#do_import`. They slot into `app/engine/converters/`
  behind the same `convert(src, dest) → {log:, warnings:, errors:}` contract and can
  reuse the staging-layout knowledge (notably: a converter MUST emit `managers_dir` +
  `managers_pattern` or the importer silently skips `managers/*`). Needed when someone
  hands over a package file and there is no DB access; NOT needed for the c2→production
  flow above. Size: ~1 day per format + fixtures.
- **Mode B replay gate (CMS-source) before any bulk clone.** The 2026-08-02 validation
  was a hand-rolled script. Committing it as a CMS source mode in the existing
  `Replay::` harness (reuse `ReplayGrader`/`ReplayDiff`; new pieces are a CMS submission
  sampler and a CMS-outcome→cafe-verdict-char translator) turns per-task validation into
  one command. Matters because the 8-submission check only exercised white-diff +
  integer GroupMin + grader compilation; `Sum`, regex GroupMin params, and comparator
  (`custom_cms`) checkers have never been run against a real task. Size: ~half a day.
- Communication task support in the judge (manager process + FIFOs) — unblocks CMS Communication import/export.
- OutputOnly grading support — unblocks CMS OutputOnly import/export.
- GroupMinPrereq scoring in cafe's scorer (`score_param` to hold the prereq DAG) — unblocks importing dae's CMS camp tasks that use the custom score type.
- File-I/O task support (or a permanent-rejection decision) for Italian-format tasks with `infile`/`outfile`.
- Checker protocol adapter so `custom_cafe` checkers can be exported to CMS.
- C++ relative comparator (CMS-side equivalent of `lib/checker/relative.rb`).
- ✅ DONE 2026-07-19 — group-weight uniformity warning in the dataset UI
  (`Dataset#mixed_weight_groups`, shared with the import warning) and CMS-style
  codename-regex grouping in the Testcase config tool; the weight/group grammar
  and the CMS-divergence caveat are documented in `doc/dataset-scoring-and-evaluation.md`.
- Approach-C IR refactor of import/export — only if supported formats multiply beyond Italian+TPS.
- ✅ AUDITED 2026-07-19 — every single-string shell invocation on the grading path
  (`isolate_runner.rb`, `checker.rb:155`, `compiler/postgres.rb`, `judge_base.rb`,
  `grader.rb`). **Finding: no untrusted (student) input reaches any command
  string** — inputs are deployment config, engine-built ID paths, the
  admin-managed `languages` table, and problem-author files; authors already have
  arbitrary code execution by design (custom checkers run *unsandboxed* at
  `checker.rb:155`). Action taken: `judge_base.rb#run_initializer` → argv
  `system(*init_cmd)`; `check_command` → argv DONE (rev 2212, issue #49: a
  checker uploaded as "checker (1)" failed in the shell string). Optional
  hardening left: `${UID}` → `Process.uid` so `run_isolate` can drop the shell. **Separate larger item:**
  move custom checkers inside isolate if checkers are ever accepted from
  less-trusted authors.
- ✅ FIXED 2026-07-19 — `test/controllers/` and `test/integration/` must not declare
  the same class name (Ruby merges them and cross-contaminates `setup`); the
  integration file is now `report_controller_access_test.rb` /
  `ReportControllerAccessTest`. The rule stands for new test files.

---

## Near-Miss: student-facing phase (deliberately deferred)

Interaction model (staged ladder vs one-click AI repair vs mode-split),
lifeline economy via the existing `comments.cost` machinery,
GraderConfiguration budget keys. Deferred until the batch data is digested —
the contest-scale evidence now exists; see `doc/Near-Miss-Grading.md`
(experimental record + the max(original, repaired) policy) and spec
section 13 (`docs/superpowers/specs/2026-07-30-near-miss-grading-design.md`).

---

## Near-Miss: `problems.statement_text` — designed 2026-07-31, deferred

Decision (dae): statements reach LLM prompts as **pdf-reader-extracted text**,
stored on the Problem as an **editable draft** (the `GroundingMaterial
#extraction_draft` pattern), because raw extraction drops Thai combining
marks and humans must be able to fix it once. Consumer: the ASSIST path
(unblocks `SelfHostAssist` in the picker) — NOT repair, which measured
better without statements. Integrity design (agreed after the
clobbering-vs-staleness discussion):

| Piece | Rule |
|---|---|
| `statement_text` (mediumtext) | machine draft or human-edited text |
| `statement_text_auto` (bool, default true) | true = safe to regenerate; any human form-save sets false |
| `statement_text_checksum` (string) | statement blob checksum the text was extracted from / edited against |
| Upload hook | re-extract ONLY if auto or blank — never clobber human edits |
| Problem form | textarea + staleness badge on checksum mismatch + explicit "Re-extract from PDF" button (resets auto) |

Plus: `pdf-reader` graduates into the Gemfile; blank extraction (scanned
PDFs) leaves the field blank and prompts omit the section; leave the column
out of the audited attrs (derived, bulky).

---

## CMS clone — deferred hardening batch (from 2026-08-02 final review)

- Nil CMS `time_limit`/`memory_limit` convert to `0` silently via `.to_f`/`.to_i`
  — add a reject-or-warn guard. `app/engine/converters/cms_dump_converter.rb:284-285`
  (`write_dataset_into`).
- Fractional `GroupMin` points truncate to an int weight with no warning —
  add a warn when `points` isn't a whole number.
  `app/engine/converters/cms_dump_converter.rb:172-202` (`build_group_plan`).
- `Errno::EPIPE` on the ssh stdin write surfaces as a raw backtrace instead
  of a clean `abort` — rescue it. `lib/tasks/cms.rake:36` (`stdin.write(File.read(script))`).
- Add `-o ConnectTimeout=10` to the ssh invocation so a dead/unreachable CMS
  host fails fast instead of hanging on the default TCP timeout.
  `lib/tasks/cms.rake:31` (the `ssh -o BatchMode=yes ...` cmd array).
- An empty ACTIVE dataset (0 testcases) imports with no warning — give it
  root parity with the additional-dataset warning path (non-active empty
  datasets already get a `skipped non-active dataset` warning via
  `dataset_reject_reasons`; the active one has no equivalent signal).
  `app/engine/converters/cms_dump_converter.rb:127-147` (`dataset_reject_reasons`),
  `:327` (the per-dataset testcase-count log line).
- `script/cms_extract/extract_task.py`'s module docstring documents exit
  codes `0 ok, 2 usage, 3 task not found` but not the traceback/exit-1 case
  for an unhandled exception (e.g. `cmsDumpExporter` failure) — the rake
  task already treats any nonzero exit as failure so behavior is correct,
  just undocumented. `script/cms_extract/extract_task.py:1-21` (docstring).

---

## Waiting for a signal

### Language-specific options in the database (issue #42) — fold into the worker overhaul

**The ask (dae, 2025-06-12):** everything that depends on the submission's
language — compile command, isolate options, editor syntax mode, default
filename — should be configurable, not hard-coded.

**Done already (2026-10-01 audit):** the `languages` table (`name`,
`pretty_name`, `ext`, `common_ext`, `binary`) has an admin CRUD page
(`LanguagesController`; the seeded languages are read-only, custom ones
editable); the submission filename is per problem (`problems.submission_filename`,
falling back to `Language#default_submission_filename`); which languages a
problem accepts is per problem.

**Still in code, keyed by `Language#name`:** the compile command (one class per
language under `app/engine/compiler/`, chosen by `Compiler.get_compiler`;
compiler binaries from `config/worker.yml` `compiler:`), the sandbox options
(`JudgeBase#isolate_options_by_lang`, `#isolate_need_cg_by_lang`), and the
editor mode (`ApplicationHelper#get_ace_mode`, plus the Ace mode list in
`config/importmap.rb`).

**Why not a one-day job:** a first slice — `ace_mode`, `isolate_options`,
`need_cg` and a compile-command template as new `languages` columns, seeded
from today's constants and read by the engine — fits in a day for the simple
compiled languages. Java (classname detection in `pre_compile`), Python/Ruby
(`post_compile` for scripts), Digital and PostgreSQL carry per-language Ruby
hooks that a template cannot express, and every change here lands on the
grading path of every judge host. With a worker overhaul planned, a half-way
DB schema now would be designed twice.

**Reopen when:** the worker overhaul design starts — make "language = data,
not code" one of its requirements, and migrate the seeded constants then.
Size then: medium (schema + engine readers + admin form + migration of the
constants). Until then, new languages keep arriving as code.

**Reopened 2026-10-04:** the worker overhaul design is
`docs/superpowers/specs/2026-10-04-judge-worker-pool-design.md`. Its
envelope carries the per-language values (§6.3, §9.4); phase 0 collects
today's constants into a `LanguageProfile` registry (slice 0.4) and the
`languages` columns are slice 1.8, optional within phase 1.


Decided, not deprioritized: each of these stays closed until its **Reopen
when** condition is met. Reviewed 2026-09-02 with dae.

### Help drawers — first-visit popover on the `? Help` trigger

**Settled (2026-05-17, CLAUDE.md "Frontend & UI Conventions"):** two help
patterns coexist on purpose — inline knowledge card on index/overview pages,
offcanvas drawer on edit/detail pages — and the drawer trigger is a *labeled*
`? Help` button, never icon-only. Shared drawer layout
(`shared/_help_drawer.html.haml`, 2026-07-01) and the accordion edit drawer
(`problems/_edit_help`, 2026-07-19) are done. The old student-facing
`app/views/main/help.html.haml` (2013-era submit instructions, i18n) was
deleted with its route, action and `help.*` keys (rev 2213, issue #35); a
student help link, if one returns, should point at the wiki.

**Not built:** a first-visit popover pointing at the trigger, on the
cookie-based `dismiss-announcement` controller pattern. The hypothesis is that
the visible label alone is enough discoverability.

**Reopen when:** there is evidence the label is not enough — admins asking
where the help is, or drawers that measurably never get opened. Not a date.

### Grounding materials — three follow-ups deferred by the 2026-07-19 design

**Settled (spec `docs/superpowers/specs/2026-07-19-viva-grounding-materials-design.md`,
reaffirmed 2026-07-20, re-filed here 2026-09-12 with dae):** `GroundingMaterial`
is its own model with the Manage → Grounding library and a viva-only attach
select (`doc/Viva-Exam.md` §3); `llm_prompt` stays a `Tag` kind with exactly one
consumer (`comment_assist.rb`); grounding files are PDF-only; the ≈token figure
is a byte-size proxy (`BYTES_PER_PROXY_TOKEN = 400`) shown for information only.

**Not built, on purpose:**
- (a) one shared LLM-asset model for `llm_prompt` tags and grounding materials
  (alternative C in the spec) — would let `Tag` become a pure label table, for
  no benefit today.
- (b) a `pdf-reader` page count behind `GroundingMaterial#compute_estimated_tokens`
  — nothing gates on the number; it appears only in the library table, the viva
  form line "Attached grounding ≈ N tokens — re-sent every turn" and the kit
  importer log.
- (c) image grounding files. v1 originally accepted png/jpeg/webp at upload, but
  `Llm::Request.encode_pdf_part` only emits PDFs, so an image was accepted,
  token-counted and silently never sent; `ALLOWED_CONTENT_TYPES` was narrowed to
  PDF. Adding images back means extending BOTH the validation list AND the
  encoder (a sibling emitting a plain `data:image/png;base64,…` part) in the
  same change — either alone reintroduces the silent drop.

**Reopen when:** (a) the prompt tag needs files or per-item token budgeting;
(b) the shown ≈token number misleads a real decision about what to attach;
(c) a course actually wants a diagram or slide image as grounding. None of
these has happened.

### `ai_gateway:` holds ONE gateway — no second bearer-key gateway side by side

`Llm::AiGatewayTransport.gateway_config` (`app/services/llm/ai_gateway_transport.rb`)
reads a single `Rails.configuration.llm[:ai_gateway]` block, so a deployment
runs exactly one bearer-key gateway. Running two concurrently — the Chula AI
Gateway *and* an OpenRouter-style aggregator held as a fallback for when a
model retires or the proxy wobbles — needs `ai_gateway:` generalized into a
keyed registry shaped like `self_hosted_models:`, plus a provider class per
entry so the admin pickers can tell the two rosters apart. Size: medium —
config shape, initializer wiring, per-entry provider classes, picker plumbing.

**Not built (2026-08-30):** this is the YAGNI half of the old "OpenRouter LLM
provider" entry. Nobody runs two gateways today, and a single-gateway
deployment is fully served by the current block — *including* a downstream
site whose only gateway is OpenRouter. The other half (provider-agnostic cost
+ a documented recipe) shipped at rev 2050; see Resolved.

**Reopen when:** a second *concurrent* gateway is actually wanted — a
fallback aggregator to run beside the Chula AI Gateway, a second provider the
pickers must tell apart, or a deployment that needs two bearer-key gateways.
Adding a new provider that *replaces* the current one is not a signal; the
existing block already handles that with a config change.

---

## Resolved

Pointer blocks only — newest first. Full write-ups: `hg log`, CHANGELOG, linked docs.

### Testcase visibility vs. scraping (issue #18, with #59) — RESOLVED 2026-10-01

**Rev 2218.** A preview tier: students the flags admit see the first
`ui.testcase_preview_bytes` (default 2048) of each input, expected output and
run-time data file, no downloads; admins, reporters and editors get whole
files. One predicate, `User#testcase_access`, decides everywhere (page,
downloads, API) and now checks the problem's own flag too, which the
downloads and the API skipped. Managers stay whole. Record: CHANGELOG
[Unreleased] (Added + Security), `doc/decisions.md` 2026-10-01. Residual:
none; option 4 (download logging, rate limits) was not needed once
downloads left the preview tier.

### Contest AI Usage page — grades undercounted, blank status, unlabelled units — RESOLVED 2026-09-25

**Rev 2207.** Grades counted by session start (not `graded_at`): DS Quiz 1
went from 23 to 151; status column filled for turns and assists; every wait
column in seconds with p50–p99 explained; AI time (mean, p95) beside the
wait in the distribution and by-model tables. Record: CHANGELOG
[Unreleased]. Residual: the contest-report direction entry above.

### Contest page: show how many viva gradings are still in flight — RESOLVED 2026-09-24

**Rev 2201.** `Contest#viva_grading_counts` (evaluating and grader_error
sessions over the Finish-open-vivas scope) behind a status badge next to
**Finish open vivas** on `contests/show`, served by `contests#viva_status`
into a turbo frame and refreshed every 10 s while anything is grading; reads
"All vivas graded" when the scores are final. Not added to the AI-usage
report. Record: CHANGELOG [Unreleased], `doc/viva-visibility.md`,
`doc/Viva-History.md` 2026-09-24.

### Viva grade history — make "regrade" a feature instead of a script — RESOLVED 2026-09-23

**Revs 2183–2192**, spec `docs/superpowers/specs/2026-09-23-viva-grade-history-design.md`.
One `viva_grades` row per grader run; `superseded_at IS NULL` marks the
current grade; Re-run keeps the old row and decides under never-lower ("Keep
the higher grade", default on); the Admin card lists the history with Make
current; `bin/rails viva:regrade PROBLEM= [CONTEST=] [MODEL=] [ALL=1]
[REPLACE=1] [LIMIT=] [APPLY=1]`, `viva:regrade_status`, `viva:regrade_revert`
replace the course-prep toolkit; `rubric_version` written on every run.
Record: CHANGELOG [Unreleased], `doc/Viva-History.md` 2026-09-23,
`doc/Viva-Exam.md` "Regrading a cohort".

### Contest stop does not finish open viva sessions — RESOLVED 2026-09-23

**Rev 2161.** Raised from the Quiz 1 postmortem (F5: 65 sessions open at the
bell, 62 Re-run clicks); decided 2026-09-17 as a batch button, not a
contest-stop trigger. "Finish open vivas" on `contests/show` runs
`Contest#finish_open_vivas!` over the contest window (same rules as
`Contest#submissions`) and toasts graded / archived / skipped-in-flight
counts; the two branches moved into `Submission#finalize_open_viva!`, shared
with the 24 h reaper and now under the row lock `#answer`/`#finish` use.
Audit row `finish_open_vivas`. Phase B's automatic window-end force-finish
and the session wall clock stay open in `doc/Viva-Exam.md`. Record:
CHANGELOG [Unreleased], `doc/Viva-History.md` 2026-09-23.

### `viva:import` updated `viva_prompt` on prod without an audit row — RESOLVED 2026-09-17

Root cause (reproduced with a dev-DB probe and `test/models/auditable_test.rb`):
`Auditable` read `saved_changes` in `after_update_commit`, but `reload` clears
it — and `KitImporter#post_check` reloads every touched problem inside the
import transaction, so the commit callback saw an empty diff and returned. The
same read also mis-reported two other shapes: several saves of one record in
one transaction logged only the last save's fields, and a record created then
updated in one transaction got a create row carrying only the update's field
(`create_problem` does exactly that with `live_dataset`). Fix, rev 2157 (chula_cp
2158): the concern stages the tracked `saved_changes` in `after_save` and writes
them at commit — first old / last new per field, changed-and-changed-back
dropped, `after_rollback` discards the staging, and a save under
`AuditLog.paused` stages nothing (pausing inside an outer transaction used to
leak the row at commit). The importer is unchanged; its reload is legitimate.
`description` joined `Problem`'s audited list, stored in full (max 6 KB on
prod). Tests: 6 new concern tests + 1 importer test asserting one `update` row
naming `description` and `viva_prompt` (redacted) with the rake's actor note.

### Deploy has no automatic post-deploy grading check — RESOLVED 2026-09-17

Shipped web rev 2155 (master; chula_cp merge 2156) + automation rev 63. The
entry's `--pick` option: `EngineSmokePicker` (`app/engine/engine_smoke_picker.rb`)
chooses the submission on each host — done, regular (no near-miss shadow),
non-viva, full score, C++ then C then Python, slowest testcase ≤ 50 % of the
time limit (no P↔T flips), graded after the live dataset and its testcases
last changed (the stored grade is against the dataset the run uses),
testcases × limit ≤ 60 s, most recent first (its blobs are still on disk).
`bin/rails engine:smoke SUB=auto` runs it and prints `SKIPPED` (exit 0) on a
web-only host (no enabled `GraderProcess` rows) or when nothing qualifies, so
neither blocks a deploy; explicit `SUB=<id>` never skips. The deploy job runs
it right after `assets:precompile` and BEFORE the Solid Queue / Passenger /
`Grader.restart` steps: `set -e` aborts the remote script on exit 1 (engine
error) or 2 (verdict differs), leaving the long-lived graders on the old code.
The two hand scripts (`~/cafe-grader/deploy_cedt.sh`, `deploy-cp-grader.sh`)
carry the same line. Checked on the dev prod-copy DB: picked a 10-testcase
C++ submission in 2.6 s; the run itself 404s locally because the testcase
blobs exist only on the servers (10 attached in DB, 0 files under `storage/`)
— the very failure the recency rule avoids on a host. Tests:
`test/engine/engine_smoke_picker_test.rb` (10). Residual: the entry's third
option, a never-deleted smoke problem seeded per host, was not built — the
`SKIPPED` path covers a fresh host, and a real host always has recent
full-score C++.

Follow-up 2026-09-25 (rev 2203): that last claim was wrong on comprog-grader,
a Python course whose newest full-score C++ was from 2024, on a problem since
limited to Python. `Submission#assign_language` (run by the engine's own
validating save) relabelled it Python, the C++ crashed as Python, and deploy
job 897 stopped on a false exit 2; `restore!` did not put `language_id` back
(three comprog submissions, 1967623 / 1917720 / 1887841, set back to C++ by
a one-off runner script). The picker
now requires a language the problem still accepts, `EngineSmoke` restores
`language_id`, and it grades from no Evaluation rows (the evaluator's crash
path keeps a found row's score, so the log showed `crash score=1.0`). The same
relabelling happens on an ordinary rejudge of such a submission — left as is:
it only touches submissions made before their problem's language list changed.

### `jobs.status` has no index, and the judge polls it at 5 Hz per grader — RESOLVED 2026-09-08

Shipped rev 2115: migration `AddStatusPriorityIdIndexToJobs` adds
`(status, priority DESC, id)` — leading column for `Job.has_waiting_job` and
`Job.reclaim_orphaned!`, full key for `take_oldest_waiting_job`'s sort with
no filesort — and `Job.clean_old_job` now also purges `error` rows after 30
days (they were never deleted; on 2026-09-08 comprog carried 4,422 and cedt
1,301 dead rows from the 2026-08-30 outage, all "Output file … does not
exists"). Measured first, as the entry asked, on a `CREATE TABLE … LIKE jobs`
copy in the dev DB (MySQL 8.0.46, 128 MB pool, fsync per commit, like prod),
1,000 ops each and an 8-grader drain of 1,200 jobs with the real 0.2 s
empty-claim sleep:

| | 33k no index | 33k index | 200k no index | 200k index |
|---|---|---|---|---|
| idle poll | 2.31 ms | 0.15 ms | 13.6 ms | 0.15 ms |
| claim (select for update + flip) | 13.9 ms | 2.70 ms | 67.0 ms | 2.55 ms |
| insert / report | 2.2 ms / 2.2 ms | 2.1 ms / 2.4 ms | 2.3 ms / 2.2 ms | 2.1 ms / 2.2 ms |
| drain, 8 graders | 18.7 s | 5.5 s | 55.0 s | 5.5 s |
| empty claims of 1,200 | 353 | 0 | 655 | 0 |
| `ADD INDEX` | — | 100 ms | — | 443 ms |

The decisive finding was not speed but locking: under REPEATABLE READ the
unindexed `FOR UPDATE SKIP LOCKED` claim locks every row it scans, so a
concurrent grader's claim returns nothing (it then sleeps 0.2 s) and web-tier
job inserts wait behind the claim. With the index SKIP LOCKED does what the
2023 "start new judge" commit added it for. Write cost of the index was not
measurable — each insert/update is dominated by the commit's log flush.
Production shape that day: grader-2023 ~27k jobs/day, ~33k rows resident
after the nightly trim, 8 graders on 10.0.5.81. Same day on prod: duplicate
crontab cleanup lines removed from .50/.52/.80 (Solid Queue recurring owns
both cleanups there; the cron `cleanup_judge` on .81 stays — the worker runs
no Solid Queue). Residual: prod's dead `error` rows go on the first nightly
run after deploy; toi was unreachable over ssh and unchecked.

### Viva `answer` action — concurrent at-cap POSTs can double-enqueue the grade job — RESOLVED 2026-09-06

Shipped rev 2114. `#answer` and `#finish` (the same three lines: closing turn,
`:evaluating`, grade job) now run their check-and-transition inside
`@submission.with_lock` and enqueue after the block commits; the shared step
is `#force_finish!`. The same lock closes the below-cap variant too — two
answers landing together used to record two student turns and two assist
jobs. Regression tests: the three "concurrent" tests in
`test/integration/viva_sessions_controller_test.rb`, which play the
first-committed request through a one-shot hook on `Submission#lock!`.
Residual: `#retry_turn` and `#restart` are still lock-free — a double-click
on Retry can run one turn's LLM call twice (the second result overwrites the
first), and Restart can archive a session just as an answer lands. Cost and
nuisance only, no grading path; reopen if either shows up in transcripts.
Timeline entry: `doc/Viva-History.md` 2026-09-06.

### Problem stat page — slow page + "By group" card — RESOLVED 2026-09-03

Shipped rev 2081, both halves together as the entry proposed. `Problem#attempt_summary`
and `Problem#group_stats_for(user)` (`app/models/problem.rb`) replace the Ruby
loop over every submission (the 65-day histogram it also built was displayed
nowhere and is gone); the submissions table is filled by `problems#stat_query`
(JSON, jbuilder) and paged client-side with deferred rendering. The
"established server-side pattern" the entry pointed at (`process_query_record`)
turned out to have no callers, so the table follows the Submission report's
pattern instead. Measured on the prod-copy dev DB, heaviest problem (7,825
subs): page server work ~1.2 s of Ruby → ~0.4 s of SQL, rows (~0.2 s) fetched
separately after paint, no 7,825-row HTML. Card: members (enabled `user` role
only), solved / attempted, solved %, mean best over attempted, row links to the
Best Score report pre-filtered to the group; the distinct-user summary is kept
separate so multi-group students don't make the page contradict itself.
Rev 2082 (dae, 2026-09-03: "we have lots of groups"): prod-copy numbers are
median 5 / p90 9 / max 13 linked groups per problem, growing by the archived
cohorts each semester, so archived groups fold behind a toggle while live ones
stay open; tabs were rejected because they hide the comparison the card exists
for. Tests: `test/models/problem_group_stats_test.rb`, additions to
`test/controllers/problems_stat_controller_test.rb`, `test/system/problem_stat_test.rb`.
Residual: the remaining ~0.4 s is MySQL reading wide `submissions` rows through
the `problem_id` index; a covering index `(problem_id, repaired_from_id, user_id, points)`
would cut it further if a problem ever feels slow again. True server-side
paging (`serverSide: true`) stays an option past ~50k submissions.

### `datatables/configs.js` render functions interpolate unescaped HTML — RESOLVED 2026-09-02

Shipped rev 2079, wider than the entry asked for. The audit showed the entry
understated it: every plain `{data: 'field'}` column in every JSON-fed
DataTable rendered markup (DataTables writes cells with innerHTML), a
self-registered user sets their own full name, and the login-failure report
shows the raw attempted-login string — stored XSS from a student or an
anonymous visitor to an admin, not admin-on-admin. Fix:
`cafe.dt.escape_columns_by_default` (`app/javascript/cafe_datatable.js`) on
every JSON-fed `columns` array — the `datatables--init` controller plus nine
inline tables — and `escapeHtml` on the custom renderers' free-text
interpolations; DOM-sourced tables untouched. Regression: system tests on the
contest and group user tables (`<b>`, `<img onerror>` in a full name → text,
no element, handler never runs). Rule for new tables recorded in CLAUDE.md
(Admin DataTables). Residual: none known.

### Upstream GitHub Pages for docs/ — RESOLVED 2026-08-31

**Rev 2070 (pointer swaps; the switch itself was a GitHub setting).** jittat
enabled Pages on cafe-grader-team (Deploy from a branch, `master` + `/docs`);
verified `status: built` and both the index and `guide/authorization.html`
serving 200 over HTTPS. Same day the three pointers moved to
`https://cafe-grader-team.github.io/cafe-grader-web/…`: the upstream wiki
`Users-Roles-and-Access-Control` companion block (fork-hosting caveat
trimmed), `README.md`'s Guides-site link (rev 2070), and the fork wiki
`Home.md` "temporarily published" sentence. Residuals: upstream's README copy
catches up at the next `/upstream-sync` batch; "Enforce HTTPS" is unticked
(cosmetic, jittat's toggle); the per-repo About-field wording idea from the
old entry stays unasked-for and lives only here.

### Jobs stuck in `:process` forever when a grader dies mid-job — RESOLVED 2026-08-30

**Rev 2060.** `Job.reclaim_orphaned!` returns jobs whose grader claimed them and
never reported back. Two callers, deliberately different in how each proves the
grader is gone: `Grader.watchdog` passes the ids of boxes its own `ps` sweep
just found empty — proof, not a timeout, so a merely-slow grader can never have
its job taken away — and a `grader_job_reclaim` recurring task
(`config/recurring.yml`, every 10 min, `older_than: 30.minutes`, production
only) sweeps fleet-wide for the case the ps path structurally cannot cover: a
host whose watchdog is itself not running.

**The part that needed deciding was not detection but what to do with an old
one.** Requeueing is safe in the abstract — compile/evaluate/score are all
re-runnable and `Evaluation` is `find_or_create_by` per (submission, testcase) —
but the prod-copy dev DB held **126 stranded jobs, the oldest 564 days**, from a
worker that died 2025-08-04; ten of their eleven submissions had since been
hand-rejudged to `done`. Blind requeueing would have silently regraded
year-old submissions and, for those, failed anyway: `Grader.cleanup_web` purges
the compiled binary `Evaluator#prepare_executable` re-downloads. So a job is
dead-lettered to `:error` rather than requeued when its submission already
reached a `Submission::GRADING_FINAL_STATUSES`, when it is older than
`Job::MAX_RECLAIM_AGE` (24 h), or after `RECLAIM_ATTEMPT_LIMIT` reclaims —
sharing the `"retry N"` counter `Grader#check_and_run_job` already parses, so a
job that keeps killing graders cannot loop forever. A still-mid-flight
submission is marked `grader_error`, which is what stops a student seeing
"evaluating" forever and puts it on the normal Rejudge path.

Also: `Grader#initialize` now writes `pid`/`host` on the `GraderProcess` row —
the columns existed but only the dead legacy `register_grader` ever set them.
Nothing depends on the value; the watchdog still identifies processes from `ps`.

Tests: `test/models/job_reclaim_test.rb` (11). Dry-run against the 126 real rows
inside a rolled-back transaction: 0 requeued, 126 dead-lettered, **0 submissions
touched**. **Residual:** the missing `jobs.status` index, now its own open entry
above. Not covered: the narrow window where a grader dies *after* `Job#report`
but *before* `add_evaluation_jobs` / `add_scoring_job` — the job is `:success`,
so no `:process` sweep can see it, and the chain still stalls.

### OpenRouter LLM provider — RESOLVED 2026-08-30 (generic path hardened, recipe documented)

**Rev 2050.** The entry asked for an OpenRouter provider; the generic one had
already landed (`Llm::AiGatewayTransport`, rev 2018), so what was actually
missing was (a) cost resolution that does not assume LiteLLM and (b) a recipe a
downstream operator can follow. Both shipped. **No OpenRouter-specific code
path exists, and none is wanted** — pointing the `ai_gateway:` block at it is
configuration.

- `compute_cost` resolves header → `usage.cost` in the response body → `0.0`
  **at WARN**. The silent zero was the real defect and was never
  OpenRouter-specific: cost tracking off on the proxy, a model missing from
  LiteLLM's price map, or an upgrade dropping the header each recorded $0.00
  into `Comment.cost_summary_for` and the near-miss lifeline budget with no
  signal at all. `execute_call` now keeps the raw header string, so a genuine
  `0` stays authoritative instead of falling through.
- New optional `ai_gateway.usage_in_body` sends `usage: {include: true}`, which
  is what makes a body-reporting gateway emit cost. Off by default: LiteLLM has
  no such key and would forward the unknown field upstream.
- **The trap worth remembering** (measured, not assumed): `execute_call` POSTs
  an *absolute* path and Faraday resolves it against `base_url` with URI-join
  semantics, so an absolute path REPLACES the prefix's path —
  `https://openrouter.ai/api` + `/v1/chat/completions` silently becomes
  `https://openrouter.ai/v1/chat/completions` (404). The documented recipe keeps
  `base_url` bare and puts the whole `/api/v1/...` in `completion_path`. LiteLLM
  proxies mount at the root and are unaffected.
- Worked OpenRouter block in `config/llm.yml`, explicitly labelled UNVERIFIED on
  the two points that need a live account: the exact `usage.cost` opt-in, and
  whether OpenRouter accepts the OpenAI `file` content part that
  `convert_pdf_parts` emits for PDFs (built and tested against LiteLLM; only
  viva grounding and statement PDFs depend on it).

Tests: `test/services/llm/ai_gateway_transport_test.rb` — header wins over body,
a genuine header `0` is authoritative and does not warn, body fallback for
string *and* symbol keys, the loud zero, and `usage_in_body` off / on /
caller-supplied. **Residual:** the multi-gateway registry, now its own open
entry above.

### `custom_cms` checker argv order on LIVE problems — RESOLVED 2026-08-29 (no mis-grading)

**Verified on production (10.0.5.50), rev 2046.** All 10 problems on the legacy
argv order — `custom_cms` 570 `d68_q3a_jobqueue`, 606 `a68_q1a_horse`, 656
`a68_q4z_guitar_array3`, 659 `a68_q4a_normal_puzzle`, and `custom_cms_raw`
649–654 `rubiks_race_1..6` (one shared binary) — expect cafe's
`(input, USER, correct)` order, so `Checker#check_command` invokes them
correctly and no submission was mis-graded. Method: pulled each checker and its
real testcase blobs, ran them locally with crafted content in slot 2 vs slot 3
(empty / garbage / the reference / a valid solution); in every checker the
verdict tracks slot 2 only and slot 3 is ignored even when it holds garbage
(656 is a Python script reading `argv[2]` as the student grid; 659 accepted a
valid `1L 2L` solution in slot 2 with `1.0` and rejected it in slot 3 — its
`main` constructs an `ifstream` on `argv[3]` and never reads it). Cross-check
from production data: students hold full-score `PPPP…` runs on all ten although
the stored reference answers are placeholders (570 a fixed token; 659 and
650–654 a byte-copy of the input) that a CMS-order checker would have graded
*as the student's output* and failed universally. **The `strings` proxy in the
original entry is wrong** — all five print `translate:*` (CMS *result*
protocol, exactly as `doc/Checker-and-Auxiliary-Files.md` teaches) yet take
testlib argv order; output vocabulary says nothing about argv order. Durable
record: `doc/decisions.md` 2026-08-29; loud naming-trap warnings now sit in
`doc/Checker-and-Auxiliary-Files.md` (plus a `cms_comparator` section that was
missing), `doc/dataset-scoring-and-evaluation.md`, `doc/CMS-Migration.md` §5.3.
**Residual — DONE rev 2047 (2026-08-30):** (a) renamed `custom_cms` →
`custom_testlib`, `custom_cms_raw` → `custom_testlib_raw` (integers unchanged;
`Dataset::LEGACY_EVALUATION_TYPES` aliases the old names on assignment); (b)
`cms_comparator` exposed in the dataset dropdown as **[CMS-NATIVE]**. Fleet census
(8 servers) in `doc/decisions.md` 2026-08-29 update; TOI-box `may2025_abcd` was
the one true CMS-order checker → `cms_comparator` + rejudge.

### Grader.watchdog duplicate-spawn → isolate box collisions (`!` results) — RESOLVED 2026-08-29

**Rev 2045 + automation rev 58.** Incident 2026-08-27 on the ISE grader
(10.0.5.70): two orphaned whenever crontab blocks (identified by the
schedule.rb path; the app dir had been renamed) ran two watchdogs per minute,
both spawned per box, and `lines.count >= 1` read the pair as healthy —
isolate "This box is currently in use" → `!` on ~130 submissions that day
(bursts Jun 23–29 and Jul 17 too); hosts deduped by hand the same day.
Code: `Grader.watchdog` takes a host-wide non-blocking flock
(`Dir.tmpdir/cafe-grader-watchdog-<worker_id>.lock`), parses
`ps -o pid,ppid,etimes,args` via `Grader.grader_processes` (every grader is
an `sh -c` → Ruby chain; the wrapper is collapsed and the Ruby leaf signalled),
and `Grader.plan_box` TERMs every duplicate but the oldest — TERM, never
KILL, see the stuck-jobs entry — and stops *all* processes of a disabled box
(was: first pid only); duplicate kills go to `Rails.logger.warn`. Rerun
idempotency: `JudgeBase#prepare_testcase_directory` `rm_f`s the previous
`stdout.txt` (a run that died with its box left it 0644/other-uid; a rerun on
another box could not truncate it — 14 of 142 rejudges on 08-27). Deploy: CI
runs `whenever --clear-crontab` (drops the legacy path-identified block,
no-op after) then `whenever --update-crontab cafe-grader`. Tests
`test/engine/grader_watchdog_test.rb`. Not done: retry on isolate `XX`
(cause removed). TOI box (10.24.0.100) crontab checked 2026-08-30: a single
watchdog block (no cleanup jobs). Follow-up rev 2053: the spawn itself leaked
fds — the spawner's mysql2 socket and RVM's fd 6 (a login-shell copy of
stderr; sshd's stderr pipe under the deploy pipeline) — so the CI-driven
`Grader.restart` (automation rev 59) hung every deploy job after
"Successfully deployed"; graders now spawn with `in: /dev/null` +
`close_others: true` (`Grader.grader_spawn_options`, tested).

### Viva grading: harden against transcript-continuation failures — RESOLVED 2026-08-29

**Revs 2024 + 2043.** (a) Prompt hardening, rev 2024: `INTERVIEWER:`/`STUDENT:`
transcript labels + trailing `=== END OF TRANSCRIPT ===` re-anchor (Claude
compliance 3/24 → 16/16, Gemini unaffected). (b) Silent nil-score grades, rev
2043: the hole was `extract_json_object` returning the first balanced `{…}` and
the write path trusting it — not "no JSON", which has raised since rev 1667.
`grade_schema_error` (numeric `total_points` 0..100, non-empty `rubric`) and
unparseable brace blocks now raise `ResponseError`; `VivaGradeAssist#respond`
(new `Llm::Request#respond` template) re-asks once — not on
`finish_reason=length` — then the existing `grader_error` path (red admin alert,
`llm_response_raw` = last body, first bad reply at WARN, Re-run picker); both
attempts' cost on the grade row. Tests `test/services/llm/viva_grade_assist_test.rb`.
(c) Interview/narrative language is a **conduct-tag** concern, not code: DS kit
`_conduct.md` §Language (examiner English-only, students Thai/English/mixed,
translation → simpler English, narrative in the student's language), deployed
as prod `viva_conduct` tag 38 and verified identical 2026-08-29; convention
recorded in `doc/Viva-Exam.md` §2.
Grader model history: gemini-2.5-flash → 3.1-pro (chula_cp rev 2008; 12-session
comparison on 10.0.5.50 `~/viva_compare_results.jsonl`) → 3.7-flash via the Chula
AI Gateway (2026-08-27 bake-off, `~/cafe-grader/bakeoff-2026-08-27/report.html`);
rev 2011 made both end paths use the grade service's default.
**Residual (policy, ~$1):** re-test `claude-opus-4-5` as grader with the hardened
prompt on all 12 sessions — strictest and most consistent (spread ≤4) in the
4-session probe; strict-vs-generous on uncovered rubric items is the instructor's
call before any exam-graded viva.

### API ↔ web parity: IP whitelist not enforced on `/api/v1` — RESOLVED 2026-08-28

**Rev 2026.** Full web parity: one predicate `User#allowed_from_ip?` backs the web
gate, a per-request 403 in `Api::V1::BaseController#authenticate_api_user!`, and
token-issuance refusal in `auth/login`; CIDR matching lives in
`GraderConfiguration.whitelisted_ip?`. Tests: `authorization_sweep_spec.rb`
(whitelist sweep over every `/api/v1` route), `authorization_spec.rb`,
`test/models/grader_configuration_test.rb`. CHANGELOG 4.5.0.

### Viva grade display — narrative doesn't belong in `grader_comment` / main list — RESOLVED 2026-08-28

**Rev 2036 (4.5.0 head).** Success path writes `Submission#viva_result_marker`
(`viva` / `viva:terminated`, from `viva_terminated_at`) to `grader_comment`; the
narrative lives on `viva_grades.narrative` only. `_submission_short` shows a
badge-as-link for viva rows plus "Interview in progress" / "Grading in
progress…" / red "Grader error" states. One-off cleanup
`bin/rails viva:clean_grader_comments [APPLY=1]` (`Viva::GraderCommentCleaner`,
report-first). Record: CHANGELOG 4.5.0, `doc/Viva-Exam.md`.

### Viva/tag markdown fields are bare textareas — add highlighting + preview — RESOLVED 2026-08-28

**Rev 2030.** `markdown_editor_controller.js` (Ace `mode-markdown`, `github`
theme, soft wrap) wraps all four textareas via
`ApplicationHelper#markdown_editor_data`, with an Edit / Preview toggle →
`POST /markdown/preview` (`safe_markdown`, editors only); `grounding-draft`
dispatches `change` so "Copy draft into Body" still works. Not done by design:
side-by-side preview, client-side renderer.

### Viva problem edit page — right column is empty, left column crammed — RESOLVED 2026-08-28

**Rev 2031.** One form over both columns: Detail card left, Viva Exam card right
(Scenario + briefing full width, then interview setup). Hint and Description tabs
dropped for viva problems; `form=` rejected because Rails does not propagate it
to a multiple select's hidden input. Type switches redraw `#problem-edit` on
save; a dataset-less problem gets an "Add dataset" empty state.

### Reporter role: let it report on finished (unavailable / archived) courses — RESOLVED 2026-07-01

**Option 3b.** Editors are group-scoped content curators:
`Problem.group_editable_by_user` dropped the `available` / `groups.enabled`
filters, `group_reportable_by_user` = editor-set ∪ reporter-gated-set, and
`Group.reportable_by_user` is role-aware — an editor sees/edits/reports on
archived courses and draft problems in their groups; reporters stay scoped to
live content. **Operational rule:** to give a non-admin access to a finished
course, make them an *editor* of its group. Option B (scores-only split) not
taken. Tests `test/models/problem_scope_authorization_test.rb`; the role model is
documented in `doc/Users-Roles-and-Access-Control.md` / the upstream wiki page
and superseded in detail by `doc/decisions.md` 2026-08-22.

### Publish "Users, Roles & Access Control" wiki page — RESOLVED 2026-07-01

Live at https://github.com/cafe-grader-team/cafe-grader-web/wiki/Users-Roles-and-Access-Control
(wiki commit `54b2c8d`). Source draft: `doc/Users-Roles-and-Access-Control.md` —
edit here, then re-push to the separate wiki repo
(`git@github.com:cafe-grader-team/cafe-grader-web.wiki.git`). Wiki `Home.md` is
intentionally minimal (GitHub's auto sidebar lists pages).

### AuditLog destroy test — RESOLVED 2026-06-20

`test/models/auditable_test.rb` (4 tests): own-row destroy writes a `destroy`
row, the `dependent: :destroy` cascade writes rows for `ContestProblem` /
`ContestUser`, the snapshot stores `[value, nil]`, `AuditLog.paused` suppresses.
Confirms `after_destroy_commit` fires under transactional tests.

### CSRF meta null-safety in DataTable inits — RESOLVED 2026-06-20

`?.` on every `meta[name="csrf-token"]` lookup — 5 view sites plus 4 in the
shared `datatables/configs.js`; a grep for the unguarded form returns nothing.
Rule codified in CLAUDE.md "Testing Notes" (the unguarded form throws when
forgery protection is off and silently kills the whole DataTable).

### System-test suite — RESOLVED 2026-06-15

`bin/rails test:system` 46/46 green (was 20 failing on 2026-05-21). Six root-cause
clusters, none of them production regressions: the no-spaces `name` rule is
intentional (`NameFormatValidator`, human text goes in `description`) — tests
fixed, not the rule; `select2_select` helper scoped to the open widget with
`exact_text`; async turbo_stream submits raced the DB read — wait for `.toast`;
submissions "Go" button replaced by the select2 chooser; users-page drift
(unguarded CSRF meta, redirect target, grant-admin select2, `f.button :submit`).
Two tests skipped on hunches were both wrong diagnoses and are un-skipped. All
lessons live in CLAUDE.md "Testing Notes". Leftover UI question: the user-edit
page's second submit button outside the form via `form=`.
