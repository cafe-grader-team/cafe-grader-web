# Submission assist — first read of the Gateway models' answers (2026-10-13)

> **Data and scripts for this study are not in this repository.** They contain
> student code and tutor answers to real students and live in the instructor's
> local `course-prep` repo, `assist/eval-2026-10-13/` (rev 26; see "Where the
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
| **wrong diagnosis** | **12 (20%)**, 8 on the hand check | **0** | 1 |
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

The other 4 are partly right. Each names a real bug or the right line, together
with a false claim: a wrong cause, a false "this part is correct", or a fix
that would not work. The four flash spot checks were all right.

Part 1 (2026-09-03, old prompt and payload, every current-model answer, no
cell weighting) had already put Opus at 11% wrong (4 of 37) and flash at 4%
(1 of 26). The v2.2 prompt did not fix Opus's accuracy.

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

1. **Opus gets the diagnosis wrong in about one answer in six (8–12 of 60);
   flash in none of 39.** Opus's errors are confident and specific. It
   misquotes the code, blames a line that is fine, or explains a time limit
   with the wrong cause, so a student who follows the answer looks in the wrong
   place. Part 1 linked wrong diagnoses to worse next submissions (39% worse vs
   18%).
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

## Decision (open, dae)

Students pick Opus about two to one (Quiz 2: 218 vs 101). Options:

- **(a)** List flash first in the picker and keep Opus.
- **(b)** Take Opus out of the picker, keeping it as a backup the way the
  Genie models were on 2026-09-09: comment out its entry in chula_cp's
  `config/llm.yml`. Flash would then be the only Gateway model until a better
  one (for example a Gemini Pro from OIT) is available.
- **(c)** Leave the picker as it is.

The measured accuracy and focus favour (b). The outcome data gives no reason
to expect students to do worse without Opus. Prompt caching then saves nothing
in practice, because flash ignores the marker. It stays harmless and ready if a
Claude model returns.

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
- The hand check was not blind.
