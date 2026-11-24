# Submission-assist (Codey) corpus evaluation — 2026-09-03

> **Data and scripts for this study are not in this repository.** They contain
> student code and tutor answers to real students and live in the instructor's
> local `course-prep` repo, `assist/eval-2026-09-03/` (see "Where the record
> lives" in `doc/Assist-History.md`). This document holds the method, the
> numbers and the conclusions only.

How well does the AI helper on coding submissions behave, and what should change
in its prompt? This is the first systematic read of the answers it has given.
It is the baseline for judging the prompt edits that follow and the payload
changes shipped the same day (master 2089–2090: compiler output, per-testcase
table, previous answer + diff, picker guards).

## Corpus

Production database as of 2026-09-03 11:44 (synced to the dev copy the same
afternoon). 5,098 assist requests since 2025-07-23; 4,787 answered on a
submission that still exists.

| Model generation | Answers | Share | Still in the picker |
|---|---|---|---|
| gemini-2.5-pro | 3,973 | 83% | no (removed from the picker 2026-08-23; the Genie relay still serves it, planned retirement ~2026-10) |
| Claude-3.5-Sonnet | 621 | 13% | no (renamed `Claude-Sonnet` on the relay) |
| gemini-3.1-pro (ChulaGenie) | 90 | 2% | yes |
| Claude-Sonnet (ChulaGenie) | 40 | 1% | yes |
| claude-opus-4-5 (AI Gateway) | 37 | 1% | yes |
| gemini-3.7-flash (AI Gateway) | 26 | 1% | yes |

Every answer was produced with the OLD payload (statement PDF, managers, source,
verdict string) and one of the two identical prompt tags (`AI-AL` / `AI-DS`, now
`codey-core` + `codey-thai`).

## Method

**Frame** (`frame.rb`, all 4,787): verdict class of the assisted submission
(CE, WA-only, TLE-only, RE-only, mixed, full), outcome of the student's *next*
submission on the same problem (improved / same / worse / none), request index
per (student, problem), and three mechanical checks — longest code block the
tutor wrote, algorithm names not present in the student's code, and "first N
tests" claims compared with the real verdict.

**Reading set** (291): every answer from the four current models (193) plus a
stratified sample of the retired models, 7 per verdict-class × outcome cell
(98; the CE/worse cell had fewer than 7). Each answer was read with the
student's source, the real per-test evaluations and compiler output, and scored
on a fixed rubric by an LLM reader (12 chunks, one reader each, strict-when-
unsure). Columns: **leak** (0 Socratic / 1 states the fix / 2 gives the
algorithm or code), **diagnosis** (correct / wrong / unverifiable against the
material), **focus** (one issue, ≤2 questions), **actionable** (ends with a
concrete step), code lines written, techniques named, language.

Caveats: one LLM reader per chunk, so strictness varies slightly between
chunks (one reader kept leading questions at leak 0, the others scored them
1); per-model counts for the current generation are small (26–90); outcome is
the next submission only, and students who ask are the ones already stuck.

## Results

### Mechanical checks over the whole corpus

| | Retired (4,594) | Current (193) |
|---|---|---|
| Repeat request on the same problem | 44% | 39% |
| Code block of ≥3 lines in the answer | 24% | 35% |
| Names a technique the student's code lacks (regex) | 34% | 23% |
| "First N tests" claim matches the verdict | 76% (of 350) | 86% (of 28) |
| Carries a Thai translation | 51% | 97% |
| Median answer length | 2.5 KB | 5.8 KB |

The regex counts overstate violations (they match quoted student code and
generic words); the read scores below are the reliable figures.

### Read scores

| Group | n | leak ≥1 | leak 2 | diagnosis wrong | focus ok | code ≥3 lines | names technique | actionable |
|---|---|---|---|---|---|---|---|---|
| **Current models** | 193 | 64% | 9% | 7% | 55% | 1% | 3% | 92% |
| gemini-3.1-pro | 90 | 63% | 2% | **0%** | 64% | 0% | 2% | 97% |
| gemini-3.7-flash | 26 | 50% | 12% | 4% | 73% | 0% | 4% | 77% |
| claude-opus-4-5 | 37 | 65% | 16% | 11% | 38% | 0% | 5% | 89% |
| Claude-Sonnet (Genie) | 40 | 72% | 15% | **20%** | 38% | 2% | 2% | 95% |
| **Retired (stratified)** | 98 | 52% | 16% | 16% | 76% | 2% | 4% | 93% |
| gemini-2.5-pro | 79 | 44% | 14% | 8% | **91%** | 1% | 3% | 96% |
| Claude-3.5-Sonnet | 19 | 84% | 26% | **53%** | 11% | 5% | 11% | 79% |

By verdict class (current models):

| Class | n | leak ≥1 | leak 2 | wrong | focus ok |
|---|---|---|---|---|---|
| Compile error | 11 | 73% | 0% | 0% | 82% |
| Wrong answer | 90 | 61% | 4% | 10% | 47% |
| Time limit | 29 | **83%** | **21%** | 3% | 59% |
| Runtime error | 17 | 76% | 18% | 0% | 65% |
| Mixed | 32 | 66% | 12% | 9% | 41% |
| Full score | 14 | 14% | 0% | 0% | 100% |

Scores against what the student did next (all 291):

| | n | next improved | next worse |
|---|---|---|---|
| leak 0 (Socratic) | 102 | 44% | 21% |
| leak 1 (states the fix) | 136 | 48% | 17% |
| leak 2 (gives the algorithm) | 31 | **32%** | **32%** |
| diagnosis correct | 229 | 47% | 18% |
| diagnosis wrong | 28 | 36% | **39%** |
| first request | 168 | wrong 6% | |
| repeat request | 123 | wrong **15%** | |

## Findings

1. **The two hard rules hold; the soft one does not.** Almost nobody writes
   code (1%) or names an algorithm (3%). But 64% of current answers state the
   fix, and 9% hand over the whole algorithm *described in words* — binary
   search as "check the middle and discard half", Dijkstra as "explore outward
   from the closest city with a structure that pulls the smallest", interval
   merging with a worked example. The "never name it" rule is obeyed to the
   letter and defeated in spirit, and it happens mostly on TLE (21%) and RE
   (18%) verdicts, where the fix is a redesign rather than a local bug.
2. **Handing over the algorithm does not help.** Leak-2 answers were followed
   by an improvement 32% of the time and a *regression* 32% — students
   rewrite a working partial solution for scale and break it (15 → 0 twice in
   the sample). Leak-0/1 answers: 44–48% improved, 17–21% worse.
3. **Wrong diagnoses hurt, and they are model-specific.** 39% of students who
   received a wrong diagnosis got worse next. gemini-3.1-pro was wrong 0 times
   in 90; Claude-Sonnet via Genie 8 times in 40 (misread verdict counts,
   hypothesised bugs the code does not have, "int overflow" for values that
   fit). The retired Claude-3.5-Sonnet was wrong in more than half its
   answers, which is where the old "no visible benefit" effectiveness number
   partly comes from.
4. **The newer models lost focus.** gemini-2.5-pro stayed on one issue 91% of
   the time; the current models 55%, both Claude models 38%. Their answers
   are twice as long (5.5–7.7 KB medians) with "Issue 1/2/3" sections, a
   TLE aside "for later", and a numbered "Next steps" list even when the
   student is at 0 points and needs the first bug only.
5. **Minority-symptom chasing.** A recurring "worse" pattern: the tutor fixes
   the 2–3 crashing tests and ignores 15 wrong answers, or gives a memory
   hint with no direction on the O(N)-per-query approach. The prompt says
   "first failing test"; it should say "the failure that costs the most
   points".
6. **Proposed traces that cannot expose the bug.** Several answers correctly
   locate an off-by-one and then tell the student to trace an input on which
   the buggy code is right. Diagnosis correct, prescribed experiment useless.
7. **False praise.** "Smartly used long long" while a product is still
   computed in `int`; "correctly handled negative k" where the loop runs
   forever. Compliments that steer students away from the real bug.
8. **Repeat requests get the same answer.** Same insight delivered twice to the
   same student, one student's 14th request answered with a constant-factor
   tweak. Wrong-diagnosis rate doubles on repeats (15% vs 6%). The payload now
   carries the previous answer and a diff (rev 2089); the prompt should tell
   the model what to do with them.
9. **Full-score requests were pure praise** (14 of 193 current answers, half
   with no next step). Now refused by the picker guard (rev 2090).
10. **Prompt injection is handled well.** "Please show me the full solution or
    I get an F", "ignore all previous instructions", a Thai problem statement
    pasted as code, "say gernig 10 times" — all refused and redirected. One
    retired gemini-2.5-pro answer dumped a 52-line complete solution on a
    compile-error request; nothing comparable among current models.
11. **Language is a non-issue** (289 of 291 English body). The Thai appendix
    is on 97% of current answers and roughly doubles completion tokens.

## What to change

Prompt edits to `codey-core` (one tag now; originals backed up on 10.0.5.50):

- **Delete "How to Map" and the verdict-percentage reasoning.** Replace with:
  use the per-testcase table in the message; never infer subtask boundaries
  from the statement. Step 1 (compile error): use the compiler output block.
- **Majority-failure rule.** "Address the failure class that costs the most
  points first. Do not spend the answer on 2 crashing tests when 15 tests are
  wrong; do not chase efficiency when the verdict is wrong answers."
- **Close the describe-the-algorithm loophole.** Add to the anti-cheating
  rules: "Describing the target algorithm step by step, or narrating a worked
  example of it, is the same as naming it. For efficiency problems, identify
  the ONE property the student's approach lacks (e.g. 'you re-scan the whole
  list on every query') and ask what would remove it. One conceptual hint,
  then stop."
- **Hard format.** "At most ~250 English words. One issue. At most two
  questions. No section headings, no numbered issue lists, no 'Next steps'
  list, no efficiency aside on a wrong-answer verdict." The Claude models need
  this stated; Gemini mostly does it unprompted.
- **Trace check.** "If you ask the student to trace an input, choose one on
  which their current code produces a wrong result, and say what the correct
  result is."
- **No unverified praise.** "Do not compliment a construct (types, bounds
  checks, complexity) unless you have verified it in the code."
- **Repeat requests.** "When a previous answer is supplied, do not repeat it.
  If the diff shows the student acted on it, move to the next obstacle; if
  not, take a different angle on the same point."
- Drop the full-score branch (the picker now refuses those).

Deployment decisions (not prompt text):

- **Model roster.** gemini-3.1-pro is the most accurate and least leaky of the
  four; Claude-Sonnet via Genie is the worst current model on every column
  and is the same class of failure the retired 3.5-Sonnet showed. Consider
  removing it from the picker or ordering the picker so gemini-3.1-pro is
  first. (Small n: 40.)
- **Thai appendix** (`codey-thai`, 239 problems): keep, drop, or switch to a
  Thai-only body. It is a cost and length question, not a quality one.

## Part 2 — outcomes over the whole corpus (same day, evening; no model involved)

The single-next-submission metric above is noisy and the "never-assisted
students" baseline is confounded (students who never ask are the ones who never
needed to). This pass recomputes outcomes over all 4,646 answered requests on
not-yet-full submissions with three better comparisons. Scripts `frame2.rb` /
`frame3.rb` in the archive; outcome columns: **next↑** = the very next
submission scored higher; **full≤3** = full score within the next three
submissions; **full≤24h**; **full-ever** on that problem; **no-later** = the
student never submitted that problem again.

### The cleanest comparison: same student, same problem, adjacent attempts

For the 1,504 first requests where the student had already submitted that
problem at least once before asking:

| Step | improved |
|---|---|
| the unassisted step just before the assist (previous → assisted submission) | 27% |
| the assisted step (assisted submission → next) | **38%** |

Eleven points, on the same student and the same problem, with the median gap
between attempts growing from 3 to 5 minutes. This is the best evidence in the
data that the hint does something; it does not separate the hint from the extra
minutes of thinking, and a student who has just failed is likelier to improve
next time regardless.

### Within-student baseline

The same 316 students' own unassisted, not-full submissions on problems where
they never asked (4,000 sampled):

| | no-later | next↑ | full≤3 | full-ever |
|---|---|---|---|---|
| assisted requests (n=4,646) | 14% | 36% | 37% | 63% |
| same students, unassisted, other problems (n=4,000) | 4% | 45% | 55% | 87% |
| students who never asked, same problems and period (n=3,636) | 2% | 76% | 57% | 91% |

Students ask on the problems that are hardest for them, so the lower assisted
numbers are what selection predicts; the never-asked row is not a valid control
and should not be quoted as one.

### August 2026: old and new models on the same 22 problems, same weeks

| | n | no-later | next↑ | full≤3 | full≤24h | full-ever |
|---|---|---|---|---|---|---|
| gemini-2.5-pro (retired 08-23) | 305 | 16% | 38% | 46% | 52% | 82% |
| current four models | 105 | 8% | **50%** | **65%** | **72%** | 75%* |

*Current-model requests are more recent, so they have had less time to reach
"ever"; the 24-hour column is the fair one. Current requests also started from a
higher score (median 10 vs 0 points). Suggestive, not conclusive: n=105 across
four models.

### Splits (assisted, not already full)

| Split | n | no-later | next↑ | full≤3 | full-ever |
|---|---|---|---|---|---|
| points at request: 0 | 2,198 | 14% | 32% | 29% | 56% |
| points 1–49 | 1,549 | 13% | 41% | 40% | 63% |
| points 50–99 | 899 | 15% | 39% | 55% | 79% |
| Data Structures (`d*`) | 2,363 | 10% | 34% | 37% | 65% |
| Algorithms (`a*`) | 2,062 | 18% | 38% | 35% | 57% |
| first request | 2,598 | 11% | 39% | 38% | 65% |
| repeat request | 2,048 | 16% | 33% | 36% | 59% |
| semester 1/2568 | 1,880 | 10% | 31% | 33% | 61% |
| semester 2/2568 | 2,250 | 17% | 39% | 38% | 59% |
| semester 1/2569 (to Sep 3) | 493 | 12% | 43% | 54% | 81% |
| verdict: compile error | 282 | 15% | **25%** | 24% | 45% |
| wrong answer | 1,861 | 10% | 42% | 50% | 74% |
| time limit | 578 | 19% | 30% | 45% | 69% |
| runtime error | 643 | 10% | 27% | 26% | 55% |
| mixed | 1,258 | 18% | 37% | 23% | 50% |

Compile errors are the worst class by every column — the case where the payload
sent nothing the model could use (no compiler output until rev 2089). Repeat
requests do worse than first ones on every column, consistent with the same
answer arriving twice.

### The 14% who never resubmit

652 requests were the student's last action on that problem. 66 of them already
held a 100 from an earlier submission (asking about an old attempt to learn),
leaving 586 apparent give-ups; 346 of the 652 were repeat requests; median hour
of day 11:00. Mixed and wrong-answer verdicts dominate.

### Problems that soak up requests

| Problem | requests | students | repeat | next↑ | full≤3 | full-ever |
|---|---|---|---|---|---|---|
| d69_q0_cv_detection | 172 | 78 | 54% | 26% | 46% | 78% |
| a68_q2a_dividing | 164 | 84 | 48% | 22% | 39% | 67% |
| a68_q2b_remaining_merge_2 | 154 | 78 | 49% | 19% | **2%** | 18% |
| a68_q1a_guitar_array | 142 | 67 | 52% | 37% | 47% | 86% |
| a68_f2_horse_running | 136 | 76 | 44% | 39% | 43% | 58% |
| d68_q1b_kv_database | 130 | 66 | 49% | 26% | 36% | 65% |
| d68_q2a_do_stack | 126 | 69 | 45% | 39% | 25% | 71% |
| d68_f2_skip_list | 123 | 59 | 52% | 17% | **2%** | 13% |
| d68_q2a_segmented_vector | 121 | 54 | 55% | 12% | 17% | 66% |
| a68_q4a_normal_puzzle | 115 | 52 | 54% | 28% | 6% | 36% |

Two problems (`remaining_merge_2`, `skip_list`) absorbed 277 requests and almost
nobody reached full score within three tries afterwards. Those are problem- or
teaching-level questions, not prompt questions.

### Verdict claims checked mechanically over all answers

"You pass the first N tests" claims: gemini-2.5-pro 246 claims, 75% match the
real verdict; Claude-3.5-Sonnet 104, 77%. The current models make such claims
far less often (4–14 each) — they read the verdict differently rather than more
accurately. "Passing N tests" claims: gemini-2.5-pro 90, 88% match.

### Who uses it, and what it cost

316 students; median 9 requests each, 90th percentile 36, maximum 131; the top
tenth of students made 38% of all requests. Tokens by semester: 1/2568 —
gemini-2.5-pro 6.4M prompt / 7.0M completion (avg 5,185 completion tokens per
answer, a reasoning model), Claude-3.5-Sonnet 5.6M / 0.28M (avg 9,091 prompt
tokens: the PDF sent as an image); 2/2568 — gemini-2.5-pro 9.4M / 13.1M; 1/2569
so far — 2.4M / 2.2M across five models. Data Structures problems consumed
14.5M prompt / 9.7M completion tokens, Algorithms 8.4M / 11.9M. Dollar cost is
recorded only from 2026-09-03 onward (rev 2089).

### What Part 2 changes in the recommendations

- The effectiveness claim for the report is the paired one: **27% → 38%** on the
  same student and problem. Do not quote the never-asked baseline.
- Compile errors and repeat requests are the two worst cells, and both are what
  rev 2089 targets (compiler output; previous answer + diff). Re-measure these
  two cells first after deployment.
- The August head-to-head is the first sign the newer models help more
  (next↑ 50% vs 38%); the read scores say Claude-Sonnet via Genie is the least
  accurate of them, so the roster decision stands.
- `remaining_merge_2` and `skip_list` deserve a look as problems, independent
  of the tutor.

## Part 3 — can the department's own models do the reading? (DGX calibration)

Same rubric, same 291 records, run as one call per record (temperature 0,
JSON output) on the two self-hosted models, then compared column by column with
the Claude read scores (`judge.py`, `agreement.py`, `judge-*.csv` in the
archive). Kappa is chance-corrected agreement; 0.4–0.6 is "moderate", 0.8+ is
what a census needs.

| Column | gemma-4-31b agree / κ | qwen3.5 agree / κ | gold rate | qwen rate |
|---|---|---|---|---|
| leak (0/1/2) | 63% / 0.31 | 70% / **0.48** | | |
| leak any (≥1) | 71% / 0.38 | 75% / 0.51 | 60% | **38%** |
| leak = 2 (algorithm handed over) | 90% / 0.15 | 91% / 0.31 | 11% | 3% |
| diagnosis wrong | 90% / 0.26 | 92% / **0.49** | 10% | 7% |
| focus | 89% / **0.77** | 75% / 0.52 | 62% | 39% |
| actionable | 95% / 0.49 | 87% / 0.25 | 92% | 88% |
| code ≥3 lines | 79% / 0.04 | 98% / 0.49 | 1% | 3% |
| names a technique | 92% / 0.21 | 95% / 0.44 | 3% | 5% |
| language ok | 100% / 1.00 | 100% / 0.67 | 99% | 100% |
| cost per record | 4 s, ~90 tokens | 55 s, ~5,800 tokens | | |

Confusions that matter (rows = gold, columns = judge):

- **qwen on leak:** of 141 answers the readers scored "states the fix", qwen
  called 56 Socratic; of 33 "hands over the algorithm", it called 12 Socratic
  and 14 "states the fix", recognising 7. It is lenient in exactly the place
  the study's main finding lives — a census on qwen would report leaks at
  ~38% instead of ~60% and algorithm hand-overs at 3% instead of 11%. When it
  does say 2, it is right 7 times in 8.
- **qwen on diagnosis:** finds 13 of the 29 wrong diagnoses (4 false alarms).
  Gemma finds 6.
- **gemma on leak:** the opposite bias — pulls everything to "states the fix"
  (57 of 117 Socratic answers) and almost never sees a hand-over (3 of 33).
- **gemma on code lines:** counts quoted student code as tutor-written (21%
  vs 1%).

**Verdict.** Neither model can replace the reader for *leak* or *diagnosis*,
which are the columns the recommendations rest on. Gemma is a good free judge
for *focus* (κ 0.77) and *language*; qwen is a usable screen for *code lines*
and *named techniques*. The disagreement is systematic (direction, not
noise), so it will not average out over a census.

Two caveats. The gold set is itself one LLM reader per chunk, so part of the
gap is gold noise; the 85 leak disagreements between qwen and the readers are
the right place for a human to arbitrate — 30 of them read by the instructor
would say who is calibrated. And the qwen prompt carried no examples; a
few-shot version anchored on 6 gold answers (two per leak level) is the
cheapest thing that could move the leak threshold, one more 30-minute run.

### Few-shot retry (option 1, run the same evening)

Six gold answers — two per leak level, chosen where the zero-shot judge had
disagreed — were added to the system prompt as scored examples, with the two
threshold rules spelled out (a leading question whose answer is the fix is leak
1; narrating the algorithm is leak 2 even unnamed). Same 285 non-anchor records.

| Column | zero-shot κ | few-shot κ | few-shot rate vs gold |
|---|---|---|---|
| leak (0/1/2) | 0.50 | 0.49 | — |
| leak any (≥1) | 0.54 | 0.49 | 72% vs 60% (was 39%) |
| leak = 2 | 0.33 | **0.65** | 13% vs 11% (was 3%); finds 24 of 31, 63% precision |
| diagnosis wrong | 0.49 | **0.23** | 5% vs 10%; finds 6 of 29 (was 13) |
| focus | 0.51 | **0.71** | 65% vs 61% |
| code ≥3 lines | 0.49 | 1.00 | |
| names a technique | 0.44 | 0.77 | |

The anchors fixed what they were aimed at — algorithm hand-overs are now
detected (24 of 31) and focus matches the readers — but the leak bias flipped
rather than vanished: qwen now calls 50 of 115 Socratic answers "states the
fix" (before: it called 56 of 141 stated fixes Socratic), so three-way leak
agreement is unchanged at κ 0.49. Diagnosis got worse: the longer prompt
crowded out the code-reading. Overall leak κ did not clear the 0.7 bar set
beforehand, so the DGX route for leak/diagnosis stops here.

**What the DGX can do for free, reliably:** few-shot qwen as a *hand-over
detector* (leak = 2, κ 0.65) and for code lines and named techniques; gemma or
few-shot qwen for focus (κ 0.71–0.77) and language. **What it cannot:** the
Socratic-vs-states-the-fix line and wrong-diagnosis detection — those stay
with a stronger reader (or a human).

**Options remaining** (decision pending):
1. Buy leak + diagnosis from a hosted model on a targeted sample (compile
   errors, repeat requests, the ten heaviest problems, the Aug-2026 overlap;
   ~650 records; ~$12–25 on Opus 5) and let the DGX fill hand-over, focus,
   code, names and language on the full census.
2. Treat the 291 as the study and move to the prompt edits; re-measure with
   the same 291-record protocol after a term, using the DGX for the cheap
   columns and a reader for leak/diagnosis.

## Offline test of the new prompt — the plan (agreed 2026-09-03; run 2026-09-04, results in Part 4 below)

The revised prompt is `course-prep` rev 4 (`assist/codey-core.md`), reviewed
and accepted by dae on 2026-09-03; it is **not** on production. Before students
see it, compare old and new prompt on the same inputs, offline:

1. **Inputs:** submissions that carry a past assist request (known moments of
   real need), not already at full score; include compile errors and repeat
   requests deliberately since those are the worst cells. The generated
   answers are throwaway — no comment rows, no charge, no student sees them.
2. **Arms, same model for every arm** (the picker's gemini-3.1-pro; optionally
   also gemini-2.5-pro, which the Genie relay still serves):
   (a) old prompt + old payload, (b) old prompt + new payload, (c) new prompt +
   new payload. (a)→(b) is what the code changed; (b)→(c) is what the prompt
   changed. Build the payload with `Llm::CommentAssist.preview`-style assembly
   against the tag texts in `course-prep/assist/` rather than the live tags.
3. **Judge:** the same rubric as Part 1 (leak / diagnosis / focus /
   actionable / code / names / language), one reader per chunk, **blind** —
   the judge must not see which arm an answer came from; shuffle and strip
   labels before grading. Grade via this Claude Code account, ~one usage
   window per 300 answers; the DGX (few-shot qwen, `judge.py --anchors`) can
   grade the cheap columns (hand-over, focus, code, names, language) on the
   rest for free.
4. **Human anchor:** dae reads 30 answers from Part 1's 291 (may run in
   parallel with the judging; the comparison happens afterwards). Page:
   `course-prep/assist/eval-2026-09-03/dae-reads.html` — 12 where the
   readers said Socratic and the few-shot DGX judge said "stated the fix", 12
   the other way round, 6 the readers called hand-overs; shuffled, no judge
   scores shown. Three questions each (gave away how much / diagnosis right /
   one issue) plus a note. Output: `dae-reads.csv` in the same directory; the
   selection key with the graders' scores is `dae-reads-key.json` there. Join
   on `comment_id` to say which judge dae agrees with on each disputed line.
5. **Success:** on arm (c) vs (a), fewer stated fixes and hand-overs, fewer
   wrong diagnoses, more single-focus answers, no rise in code written; then
   apply the prompt to tag `codey-core` (#43) on prod, cite the course-prep
   rev in `doc/Assist-History.md`, and re-measure outcomes (Part 2's
   `frame2.rb`/`frame3.rb`) after a term.

Repo state at hand-off: master 2089–2105 unmerged/unpushed (payload, guards,
accounting, tag ordering, price setting, docs); prod runs chula_cp 2088.

**When the offline test is finished, remind dae of three deferred items** (his
words, 2026-09-03: "remind me of that three things when we finished"):
1. finish the 30 human reads and save `dae-reads.csv` (then commit it in
   course-prep);
2. review master 2089–2105, merge to `chula_cp`, push, deploy to 10.0.5.50,
   run `bin/rails db:seed` there (creates `system.llm_assist_cost`) — superseded 2026-09-05: the key is
   created by a data migration (master 2111), no seed needed;
3. create the private `course-prep` project on gitlab.nattee.net and push
   (backlog entry).

How to judge the edits: re-run `frame.rb` after a term of the new payload and
prompt and compare the read-score columns and the next-submission outcomes
against this document. The scorer prompt and the frame script live in the
session scratchpad and in `course-prep/assist/eval-2026-09-03/` (local-only repo; `~/cafe-grader/assist-eval-2026-09-03` is a symlink to it) (frame CSV,
per-chunk scores, aggregation script); the raw answers are in production
`comments` and are not copied into the repo.

## Part 4 — offline old-vs-new prompt test (run 2026-09-04)

The plan above, executed. Data, scripts and every answer are in
`course-prep/assist/eval-2026-09-03/offline-prompt-test/` (revs 6–10; `README.md` there is
the file-level guide). Nothing here touched production or any student.

**Setup.** 100 real stuck moments — answered assist requests on not-full submissions from the
production copy — chosen so that the two worst cells are over-weighted: 20 compile errors and
45 repeat requests (by class: CE 20, WA 25, TLE 18, RE 14, mixed 23; at most 3 per problem,
43 problems). For each one the same model, gemini-3.1-pro via the Genie relay, wrote three
answers:

| Arm | Prompt | What the platform sent with it |
|---|---|---|
| a | old (`course-prep` rev 3, live on prod) | old payload (web rev 2088): statement PDF, managers, source + verdict string |
| b | old | new payload (web rev 2089+): + compiler output or per-testcase table, + previous answer and diff on repeats |
| c | new (`course-prep` rev 4) | new payload |

300 answers, 0 failures; the `codey-thai` addendum was kept where the problem carries it (91 of
100), identically in every arm. Genie quota used: ~1.5M input, ~1.3M output tokens (the model
reasons; ~2,600–3,800 of each answer's completion tokens are thinking). On a repeat request the
"previous answer" is the one the student had actually received before that request, never a
later one.

**Grading.** The 300 answers were shuffled, given random ids, split into 12 chunks of 25 with
the three arms of one input never in the same chunk, the Thai appendix stripped, and read by
12 Claude readers (one per chunk, Part 1's rubric verbatim) who could not see which arm an
answer came from. The free DGX judge (few-shot qwen, Part 3) also scored all 300, for the
cheaper-grader question. Two operational notes for next time: the first reader pass hit the
account's 5-hour limit after 2 of 12 chunks (12 readers × ~105k tokens is more than one window
when the session has prior usage — run 6 + 6), and the Thai-stripping heuristic cut 33
English bodies short at a quoted Thai phrase; it was fixed (a line must be mostly Thai *and*
followed by mostly-Thai text) and the chunks regenerated with identical ids before the second
pass. Three records already graded from a cut body were re-graded.

### What the readers found

| Arm | states the fix or worse | hands over the algorithm | wrong diagnosis | one issue only | ends with a step | writes ≥3 lines of code | names a technique |
|---|---|---|---|---|---|---|---|
| a: old prompt, old payload | 89 of 100 | 11 | 3 | 46 | 96 | 0 | 5 |
| b: old prompt, new payload | 90 of 100 | 13 | 0 | 51 | 96 | 1 | 7 |
| c: new prompt, new payload | 87 of 100 | 8 | 1 | **89** | 92 | 0 | 13 |

Same input, arm against arm (100 pairs each):

| | gives away less / same / more | focus gained / lost | diagnosis fixed / broken |
|---|---|---|---|
| a → b (the code change) | 7 / 83 / 10 | 17 / 12 | 3 / 0 |
| b → c (the prompt change) | 14 / 79 / 7 | **42 / 4** | 0 / 1 |
| a → c (both) | 14 / 79 / 7 | **45 / 2** | 3 / 1 |

Shape, measured mechanically on the English body of every answer:

| | a | b | c |
|---|---|---|---|
| English words (median) | 238 | 230 | **152** |
| has a numbered list | 48 | 37 | **5** |
| has section headings | 2 | 4 | 0 |
| code block of ≥3 lines (regex) | 12 | 19 | **2** |
| question marks (median) | 3 | 3 | 2 |
| completion tokens (median) | 3,848 | 3,742 | 3,064 |

By verdict class, the rows that matter:

| Class (n per arm) | hands over: a / b / c | one issue: a / b / c | notes |
|---|---|---|---|
| compile error (20) | 0 / 1 / 0 | 14 / 14 / 18 | arm c "ends with a step" fell to 15 of 20: the new Step 1 says "ask one question" and five answers ended on the question with no explicit next action |
| wrong answer (25) | 2 / 3 / **0** | 11 / 17 / **22** | the clearest win |
| time limit (18) | 7 / 6 / **6** | 5 / 8 / 16 | hand-overs did **not** fall; arm c names a tool in 10 of 18 (allowed) and then lays out the redesign anyway |
| runtime error (14) | 2 / 0 / 1 | 8 / 5 / 11 | |
| mixed (23) | 0 / 3 / 1 | 8 / 7 / 22 | |
| first request (55) | 7 / 6 / 3 | 19 / 21 / 46 | |
| repeat request (45) | 4 / 7 / 5 | 27 / 30 / **43** | the "previous answer" block plus the repeat rule ends the same-hint-twice pattern |

### Reading the result

1. **The prompt change fixes the shape completely.** One issue, at most two questions, no
   checklist, ~150 words: 89 of 100 against 46, gained on 45 inputs and lost on 2, with no
   loss of correctness (wrong diagnoses 3 → 1 across the two changes). The code change alone
   (a → b) did little for focus; the prompt text did it.
2. **It does not move the "states the fix" line.** 87–90 of 100 in every arm. Two things to
   know about that number: these readers were instructed strictly (a leading question whose
   answer is the fix counts as stating it; when unsure, score the worse), and the inputs are
   the hard cells, so the level is not comparable with Part 1's 63% for the same model on
   real answers. What is comparable is arm against arm, and there the new prompt is flat.
   Asking the model to be "Socratic" does not make gemini-3.1-pro withhold the fix; if that
   line matters, it needs a mechanism (e.g. an explicit "do not name the bug; name the place
   and ask" instruction with an example of the difference), not a principle.
3. **Hand-overs of the algorithm fall a little (11 → 8) but not on time-limit verdicts (7 → 6
   of 18).** The new TLE section allows naming the textbook tool and forbids laying out the
   redesign; the model does the first and then does the second anyway ("names binary search
   and two pointers, then lays out the per-query complement search"). Six of the eight arm-c
   hand-overs are TLE. The "one conceptual hint, then stop" sentence is not strong enough on
   its own; a concrete stop rule ("after naming the tool, ask one question and end") is the
   next edit to try.
4. **Naming textbook tools went up as intended** (5 → 13 of 100: sort, binary search, two
   pointers, path compression), and no arm wrote code (0 / 1 / 0 answers with a ≥3-line
   block by the readers' count).
5. **Small costs.** "Ends with a concrete step" slipped 96 → 92, almost entirely compile
   errors (Step 1 now says "ask one question"). Add "and tell them what to do next" to Step 1.
6. **The payload change alone (a → b) is neutral-to-slightly-positive on quality** (focus
   +5, wrong diagnoses 3 → 0, hand-overs +2) and is what makes the repeat-request rule
   possible. It is not what changes the answers' shape.

### Decision (taken 2026-09-05: rev 4 + the compile-error sentence = rev 13, live on prod; see the follow-up below)

Against the success criterion set beforehand — fewer stated fixes and hand-overs, fewer wrong
diagnoses, more single-focus answers, no rise in code — the new prompt clears "more
single-focus" decisively, "no rise in code" and "fewer wrong diagnoses" narrowly, "fewer
hand-overs" only marginally, and misses "fewer stated fixes". Recommendation: **deploy rev 4
now** (the focus gain is large and nothing got worse in a way students would feel), with two
small edits first — the Step 1 next-action sentence and a concrete stop rule after naming a
tool in the TLE section — then re-run only the TLE and CE cells of this same test (38 inputs,
~115 calls) to check those two edits before the term's outcome re-measurement.

### Part 4 as evidence for Question 2 (cheaper grader)

The DGX few-shot judge scored the same 300 blind answers. Agreement with the readers
(kappa = agreement corrected for chance; 1 is perfect, 0 is guessing):

| Column | agree | kappa | readers say yes | judge says yes |
|---|---|---|---|---|
| gave the fix away or worse | 248 of 300 | 0.28 | 266 | 250 |
| handed over the algorithm | 266 of 300 | 0.55 | 32 | 56 |
| wrong diagnosis | 296 of 300 | 0.33 | 4 | 2 |
| one issue only | 224 of 300 | 0.42 | 186 | 232 |
| writes ≥3 lines of code | 300 of 300 | 1.00 | 1 | 1 |
| names a technique | 284 of 300 | 0.59 | 25 | 17 |

The judge reproduces the *focus* ordering of the arms (68 / 70 / 94 against the readers'
46 / 51 / 89) and the flat "states the fix" line, but **inverts the hand-over verdict** (it
calls arm c the worst at 20 of 100; the readers call it the best at 8). Same conclusion as
Part 3: usable as a free screen for shape and focus, not for the leak line that the
recommendations rest on.

### Follow-up (2026-09-05): the two small edits, tested on the CE and TLE cells

`course-prep` rev 11 (`codey-core` v2.1) = rev 4 plus (1) Step 1 ends with "fix that line,
recompile, and resubmit" and (2) a hard stop in the TLE section ("if you name a tool, ask one
question about how it fits the student's current loop and end there; do not describe the steps
of the new approach, not even in outline"). Same 20 compile-error and 18 time-limit inputs, same
model, one new arm (d); the rev 4 answers (arm c) for those inputs were re-graded in the same
blind chunks by the same three readers, so the two arms are on one footing (these readers were
told an answer is "actionable" only if it ends with an instruction, not a question, so their
absolute numbers are stricter than Part 4's).

| Cell (n) | | rev 4 | v2.1 | same input, rev 4 → v2.1 |
|---|---|---|---|---|
| compile error (20) | ends with a next step | 7 | **20** | gained 13, lost 0 |
| | states the fix or worse | 15 | 16 | |
| | one issue only | 17 | 15 | |
| time limit (18) | hands over the algorithm | 7 | **9** | removed 2, introduced 4 |
| | names a technique | 9 | 12 | |
| | ends with a next step | 7 | 7 | |
| both (38) | wrong diagnosis | 0 | 0 | |

**Edit 1 works and costs nothing**: every compile-error answer now ends with what to do. **Edit 2
does not work**: told to name the tool and stop, gemini-3.1-pro names the tool *and* outlines the
algorithm in nine of eighteen answers instead of seven ("names binary search and lower_bound;
sort-then-search algorithm handed over"). A stronger prohibition in the same sentence made the
behaviour slightly worse, which matches Part 4's finding that "Socratic" wording does not move
this model's leak line. The next attempt, if any, should change the *shape* of the TLE answer
rather than add rules — e.g. a fixed three-sentence template (bottleneck, one named tool, one
question) or a second pass that strikes any sentence describing a step of the new approach —
and is parked.

**Deployable prompt: `course-prep` rev 13 (`codey-core` v2.2) = rev 4 + edit 1 only.** The
compile-error section is exactly what arm d ran; the TLE section is exactly what arm c ran, so
both halves have been read blind. Cost of the follow-up: 38 Genie calls (~0.29M tokens) and
three Claude readers (~0.33M tokens, about a quarter of a 5-hour window).
