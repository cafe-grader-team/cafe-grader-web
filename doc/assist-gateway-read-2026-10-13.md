# Submission assist — first read of the Gateway models' answers (2026-10-13)

> **Data and scripts for this study are not in this repository.** They contain
> student code and tutor answers to real students and live in the instructor's
> local `course-prep` repo, `assist/eval-2026-10-13/` (revs 26–31; see "Where the
> record lives" in `doc/Assist-History.md`). This document holds the method, the
> numbers and the conclusions only.

**Question.** Since 2026-09-10 the assist picker offers only the two Chula AI
Gateway models, claude-opus-4-5 and gemini-3.7-flash, and nobody had read their
answers (backlog: "Gateway models unread"). How good are the answers they give
real students under the current prompt (`codey-core` v2.2, live 2026-09-05
21:56)?

## Sample

99 answered requests from the production copy of 2026-10-07: 60 Opus and 39
flash, given on 2026-09-06 or later. Only the student's own requests are
included (no staff requests on a student's behalf), on submissions below full
score whose grading context can still be rebuilt, with at most 3 answers per
problem per model.

The mix of verdict classes and first/repeat requests copies the 2026-09-04
offline prompt test: compile errors 20%, wrong answer 25%, time limit 18–20%,
runtime error 15%, mixed 20–22%, first requests about 55%. That test
deliberately over-weighted the hard cells. Flash had too few time-limit repeat
requests to fill its cell (3 instead of 4).

The sample covers 38 problems: Opus 36, flash 20, of which 18 appear for both
models. The two halves are equally hard by the usual proxies: mean points of
the assisted submission 25.9 vs 27.0, median source length 44 lines for both.

## Method

- **Blinding.** The Thai translation was stripped, and every answer got a
  random id. The answers were dealt into 6 chunks of 16–17, each with about 10
  Opus and 6–7 flash answers, so one reader's strictness weighs on both models
  equally.
- **Readers.** Each chunk was read by one Claude reader who did not know which
  models were involved. The rubric is Part 1's, word for word, also used by the
  2026-09-04 test: leak (0 Socratic / 1 states the fix / 2 gives the
  algorithm), diagnosis (correct / wrong / unverifiable), one issue, ends with a
  step, code written, techniques named, language. The readers used about 600k
  tokens in total.
- **Hand check.** Afterwards the session re-checked, not blind, every answer a
  reader called a wrong diagnosis against the student's code and per-test
  results. It also spot-checked four flash answers the readers called correct.

## Results

| | claude-opus-4-5 (60) | gemini-3.7-flash (39) | gemini-3.1-pro, offline test arm c (100) |
|---|---|---|---|
| states the fix or worse (leak ≥1) | 54 (90%) | 34 (87%) | 87 |
| hands over the algorithm (leak 2) | 3 (5%) | 2 (5%) | 8 |
| **wrong diagnosis** | **12 (20%)**; all 8 that could be run confirmed | **0**; 5 run, all real causes | 1 |
| unverifiable diagnosis | 1 (2%) | 5 (13%) | — |
| **one issue only** | **29 (48%)** | **32 (82%)** | 89 |
| ends with a concrete step | 53 (88%) | 33 (85%) | 92 |
| writes ≥3 lines of code | 0 | 0 | 0 |
| names a technique | 4 (7%) | 3 (8%) | 13 |

The right-hand column is the 2026-09-04 offline test: same rubric, same cell
mix, gemini-3.1-pro on the rev 4 prompt, which is v2.2 minus one compile-error
sentence. It is a reference level, not a paired comparison.

**The wrong diagnoses are all Opus, and every reader found some** (1–4 per
chunk). On the 18 problems both models answered: Opus 7 wrong of 38, flash 0
of 37. Where they fall, Opus: wrong answer 5 of 15, mixed 4 of 13, time limit
2 of 11, runtime error 1 of 9, compile error 0 of 12.

The hand check agreed with 8 of the 12 outright:
- 5 blamed a bug that is not in the code. Examples: it misquoted the student's
  `<=` as `<`, said a correct lookup was wrong when its own worked example
  agreed with the code, and called a pop order reversed when it matches the
  sample.
- 2 gave the wrong cause for a time limit: counting about 30 loop doublings
  instead of the integer overflow that makes the loop endless, and a redundant
  lookup instead of rebuilding a whole map on every call.
- 1 blamed crashes on negative `k`, which causes long loops, not crashes, with
  wrong example arithmetic.

The other 4 looked partly right on reading (the hard check below shows they are not). Each names a real bug or the right line, together
with a false claim: a wrong cause, a false "this part is correct", or a fix
that would not work. The four flash spot checks were all right.

Part 1 (2026-09-03, old prompt and payload, every current-model answer, no
cell weighting) had already put Opus at 11% wrong (4 of 37) and flash at 4%
(1 of 26). The v2.2 prompt did not fix Opus's accuracy.

**Hard check (2026-10-14): run the code.** This check relies on nobody's
judgement. For 8 of the 12 Opus calls, plus 5 flash answers the readers
called correct, the student's own program was run on the problem's real
tests. The test files were copied from production storage, and the program
was compiled with production's flags. It was run three ways: as submitted,
changed the way the tutor said, and changed at the cause the reader named.

Every unchanged program reproduced its production verdict, apart from three
explained differences (`course-prep` rev 27, `hard/hard-check.md`). The other
4 Opus calls need class header files and were not run.

- **Opus (8 answers).** In 7, doing what the tutor said changes nothing; the
  same tests still fail. In the eighth (R048), the tutor's rewrite happens to
  rescue 2 of 4 failing tests, but the cause is an integer overflow the tutor
  never mentions. Fixing it alone passes all 20.

  Where the reader named a cause, fixing that cause made the failing tests
  pass every time:
  - R030: the output was missing its count line (16 of 20 pass; all 20 with
    `long long`).
  - R040: resize never set the size, the part the tutor called correct.
  - R083: the code reads past the end of a set, which is undefined behaviour.
    The `p + sum[bad]` lookup the tutor blamed passes all 10 tests untouched.
  - R021: moved employees keep a department that was merged away (8 crashing
    tests pass).
  - R041: floors with exactly `p` rooms were left out of the search (the
    crashes stop).

  R064 needs no run: the tutor quotes `<` where the student's code says `<=`.
  The hand check's four "partly right" cases all turn out wrong in this
  stronger sense: following the answer does not fix any failing test.
- **Flash (5 answers).** Each named cause is real. Fixing it makes previously
  failing tests pass: 3 more tests, the crashes stop, 3 more, all 20, and 9
  more once a second bug is also fixed.

**Shape** (English body, measured mechanically):

| | Opus | flash |
|---|---|---|
| English words (median) | 204 | 125 |
| has a numbered list | 2 | 16 |
| question marks (median) | 3 | 2 |
| carries a Thai translation | 41 of 60 | 27 of 39 |
| completion tokens (median; flash's include its reasoning) | 981 | 1,238 |
| price per answer (Quiz 2 mean) | $0.103 ($0.05–0.06 with prompt caching) | $0.012 |

**What students did next.** These figures cover every Gateway answer since
2026-09-06 on a submission below full score, not the sample. A next submission
counts as improved, same or worse by its points.

| | answers | resubmitted | improved | same | worse | reached 100 |
|---|---|---|---|---|---|---|
| Opus | 610 | 562 | 39% | 48% | 12% | 21% |
| flash | 284 | 259 | 43% | 44% | 12% | 16% |

## Findings

1. **Opus gets the diagnosis wrong in 12 of 60 answers; flash in none of
   39.** Running the code confirmed every one of the 8 Opus calls that could
   run: doing what the tutor said does not fix the failing tests. Every flash
   diagnosis tested this way named a real cause. Opus's errors are confident
   and specific. It misquotes the code, blames a line that is fine, or
   explains a failure with the wrong cause, so a student who follows the
   answer looks in the wrong place. Part 1 linked wrong diagnoses to worse
   next submissions (39% worse vs 18%).
2. **Opus does not keep to one issue** (48% vs flash's 82%, and the 89% the
   prompt reached on gemini-3.1-pro). It writes two-thirds more words. The v2.2
   shape rules work on the Gemini models and only half work on Opus.
3. **Both models give away the fix equally.** Both state the fix about 88% of
   the time, the same level as every arm of the offline test under these strict
   readers. Both hand over the algorithm 5% of the time, and neither writes
   code. The time-limit hand-over (backlog) shows up again: 3 of Opus's 11 time
   limits, all repeat requests.
4. **Flash's weak spot is claims nobody can check.** In 5 of its 39 answers
   the diagnosis depends on class header files that the material does not
   include. These are not counted wrong, but they are unconfirmed.
5. **What students did next does not separate the models** (improved 39% vs
   43%, worse 12% each). Students choose their model, so this cannot show
   whether one model helps more. It does show no large harm from either.
6. **Flash costs about a ninth as much,** and still about a fifth of Opus with
   prompt caching (master 2264).

## Opus with thinking (2026-10-15)

**Why.** The Gateway's Opus answers with no thinking: 0 reasoning tokens. Flash
reasons before it answers (about 500–1,200 tokens). Was the gap a weakness of
Opus, or of Opus answering without thinking?

**How.** The same 60 Opus inputs were answered again, offline, by
claude-opus-4-5 with extended thinking (budget 4,096 tokens, `max_tokens`
8,192). Each request was rebuilt exactly as production built it: the same
prompt tags, PDF, managers and grading table, and only the previous answers
the student had received by then. It was sent through the committed Gateway
code (`course-prep` rev 28, `thinking/`). Nothing was stored or shown to a
student.

The 60 new answers were mixed with 20 anchors: the 12 original Opus answers
the first read had marked wrong, and 8 it had marked correct. All 80 were read
blind by 5 fresh Claude readers on the same rubric. The anchors check that the
new readers are as strict as the first ones:
- 11 of the 12 wrong anchors were marked wrong again. The exception is R040,
  whose named bug is real but not the cause.
- All 8 correct anchors were marked correct again.

| | Opus, no thinking (first read) | **Opus with thinking** | flash (first read) |
|---|---|---|---|
| wrong diagnosis | 12 of 60 (20%) | **5 of 60 (8%)** | 0 of 39 |
| one issue only | 48% | 58% | 82% |
| states the fix or worse | 90% | 97% | 87% |
| hands over the algorithm | 5% | 7% | 5% |
| ends with a concrete step | 88% | 97% | 85% |
| English words (median) | 204 | 190 | 125 |
| time per answer (median) | 22 s (production) | **39 s** | 12 s (production) |
| price per answer | $0.103; $0.05–0.06 with caching | ≈$0.11 with caching | $0.012 |

**Same input, without → with thinking.**
- Of the 12 inputs the first answer got wrong, 9 are now correct and 3 still
  wrong: a redundant lookup blamed for a time limit, a signed/unsigned story
  for crashes, and a trailing space blamed for wrong answers.
- 2 inputs that were right became wrong. One tells the student to delete the
  semicolon that is their intended empty if-body; the other misreads the
  verdict.
- Every new reader found exactly 1 wrong answer in its 12 thinking answers.

**Hard check** (`hard/hard-check.md`) on the 8 runnable inputs where plain
Opus was wrong:
- In 5 (R030, R048, R064, R083, R041), the thinking answer names the cause
  that fixes the failing tests.
- R021 is half right: its main claim fixes nothing, its aside is the real crash
  cause.
- R040 and R076 still blame a real bug that fixes no failing test. The readers
  counted those two as correct, because the rubric accepts any real bug, so by
  the stricter standard thinking Opus is at about 7 of 60.

**Reading.** Thinking roughly halves Opus's wrong diagnoses (20% → 8–12%) and
lifts its next-step rate. That supports the explanation that Opus was weak
without thinking, not weak at the task. Against flash, this round alone
cannot rank them: 5 of 60 against 0 of 39 could be chance, about 1 time in 13.
The head-to-head below settles what can be settled. Flash answers in a third of
the time and costs about a ninth as much. Thinking also makes Opus state the
fix more often (97%).

## Quiz 2 head-to-head (2026-10-15)

**Why.** The rounds above compare different students on mostly different
problems. dae asked for the comparison on this year's exam content only.

**How.** The inputs are 60 real requests from the Quiz 2 contest `d69_q2`,
from its three non-viva problems (20 each):
- spread over failure types and first/repeat requests (30/30), in proportion
  to each problem's own requests;
- from 44 students, at most 2 per student.

Flash, Opus as production runs it, and Opus with thinking each answered **the
same 60 inputs** offline, through the committed code. Each request was rebuilt
exactly as production built it.
- One thinking request returned an empty reply after spending its token
  allowance. It is counted as a failure here (in production the student would
  see an error) and was retried once for reading.
- All 180 answers were read blind by 9 readers on the same rubric: 20 each,
  about 6–7 of each version per reader, and never two answers to the same
  input in one chunk.
- Data and scripts: `course-prep` revs 29–31, `q2/`.

| | flash | Opus (as in production) | Opus with thinking |
|---|---|---|---|
| **wrong diagnosis** | **2 of 60 (3%)** | **22 of 60 (37%)** | **7 of 60 (12%)** |
| one issue only | 73% | 47% | 62% |
| ends with a concrete step | 88% | 90% | 87% |
| states the fix or worse | 87% | 92% | 95% |
| hands over the algorithm | 8% | 12% | 3% |
| time per answer (median) | 16 s | 21 s | 51 s |
| price per answer (with caching) | $0.011 | $0.049 | $0.10 |
| wrong diagnoses, stack_super_push / vector_find / slime_tower | 0 / 1 / 1 | 13 / 6 / 3 | 4 / 0 / 3 |

**Same input, two versions** (only the inputs where they disagree count):
- **Opus vs flash, wrong diagnosis:** Opus wrong and flash right on 21 inputs,
  the reverse on 1. A split that lopsided would happen by chance less than 1
  time in 1,000.
- **Opus vs flash, not one issue:** 20 against 4 (chance about 1 in 500).
- **Opus vs Opus with thinking, wrong diagnosis:** 15 against 0.
- **Opus with thinking vs flash:** 6 against 1 on diagnosis (chance about 1
  in 8) and 14 against 7 on focus. These favour flash, but are not established
  at this size.
- **Handing over the algorithm and next steps:** no difference that holds up.

Every one of the 9 readers found at least one wrong plain-Opus diagnosis.

**Hard check** (`course-prep` rev 31, `q2/hard/hard-check.md`). Run unchanged,
the students' submissions reproduce production's per-test results on 52 of 60
inputs; the other 8 are time limits that pass on the faster local machine.

- **stack_super_push time limits (13 of plain Opus's 22).** The grader's
  element type makes every copy expensive, so the copies can be counted.
  - The four submissions checked push one element at a time: 12.7 million
    copies. Making room once per call, then assigning: 4.5 million.
  - Flash and thinking Opus told those students to make room once.
  - Plain Opus blamed the per-element copy, which every solution needs. Its
    advice to copy from `mData` crashes when followed literally, and copies as
    much or more when made safe (12.8–17.0 million).
  - Its other advice, storing (value, count) runs, is impossible in this
    problem: `student.h` may only define the two `push` functions.
- **vector_find.** Plain Opus's worked example for two inputs is answered
  correctly by the students' own code. The example meant to show the bug does
  not fail.
- **Flash's wrong call on slime_tower is real.** Doing what flash said fixes
  the 3 wrong-answer tests, but 17 time limits come from an infinite loop that
  no version named.

**Reading.** On this year's own exam problems, with every model on the same
inputs, Opus as production runs it misdiagnoses about one answer in three.
That is ten times flash's rate. Most errors are on the time-limit problem,
where Opus blames the wrong cost and recommends changes that cannot work.
Thinking cuts Opus to 12%, close enough to flash's 3% that 60 inputs cannot
separate them, but each answer takes 51 s and costs nine times flash's price.

## Decision (open, dae)

Students pick Opus about two to one (Quiz 2: 218 vs 101). Options:

- **(a)** List flash first in the picker and keep Opus.
- **(b)** Take Opus out of the picker, keeping it as a backup the way the
  Genie models were on 2026-09-09: comment out its entry in chula_cp's
  `config/llm.yml`. Flash would then be the only Gateway model until a better
  one (for example a Gemini Pro from OIT) is available.
- **(c)** Leave the picker as it is.
- **(e)** Keep Opus but with thinking on. This is a small code change on
  master: per-model extra request parameters in the `ai_gateway:` config.
  Costs: answers take about 39 s instead of 22 s, and the price per answer is
  about double the cached no-thinking price.

Today's Opus should not stay as it is: on the Quiz 2 head-to-head it
misdiagnoses ten times as often as flash. So (c) is out. That leaves:

- **(b)**, flash only. It is the most accurate version measured, and the
  fastest and cheapest.
- **(a) + (e)**, a thinking Opus beside flash. Its accuracy is not separable
  from flash's at this size, but students would wait about 51 s per answer
  (flash 16 s) at nine times the price.

The study recommends (b). (a) + (e) is the option if keeping a Claude choice
in the picker matters. The outcome data gives no reason to expect students to
do worse without Opus. Prompt caching saves nothing under (b), because flash
ignores the marker. It stays harmless and ready if a Claude model returns.

## Caveats

- One reader per chunk, and the readers are Claude models reading, among
  others, a Claude model's answers. Any self-preference would favour Opus, not
  penalise it.
- Small samples (60 and 39). If the two models were equally accurate, a gap
  this large would turn up by chance about 1 time in 650 for 12 vs 0, or about
  1 in 70 for the hand check's 8 vs 0 (one-sided Fisher exact test).
- The sample over-weights compile errors and repeat requests like the offline
  test, so the levels are not the levels for all traffic.
- Compiler messages were cut at 1,500 characters in the reading material (one
  flash answer became unverifiable because of it). Class header files were
  never included.
- The hand check was not blind. The hard check does not depend on anyone's
  judgement, but "doing what the tutor said" still had to be written as code
  by the session. Each variant is kept beside the original, so it can be
  checked (`course-prep` rev 27, `hard/`).
- The hard check ran only answers the readers had flagged (Opus) or passed
  (flash). It shows the readers' calls are right; the rate itself still
  rests on the readers covering all 99 answers.
