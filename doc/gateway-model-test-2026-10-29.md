# Gateway model test — gemini-4-argon and gemini-3.8-flash (2026-10-29)

> **Data and scripts for this study are not in this repository.** They contain
> student code, viva transcripts and tutor answers to real students and live in
> the instructor's local `course-prep` repo, `gateway-argon-2026-10-29/`
> (`report.html` is the full report). This document holds the method, the
> numbers and the conclusions only.

**Question.** The Chula AI Gateway began serving `gemini-4-argon` and
`gemini-3.8-flash` (checked with `GET /v1/models` on 2026-10-29). Should either
replace `gemini-3.7-flash`, which ran every viva role, or `claude-opus-4-5`,
the first model in the assist picker?

## Method

Every gateway feature was run offline: the local production copy of
2026-10-28, the committed `Llm::*AiGateway*` classes, the payload production
would send today, through `execute_call` only, so nothing was saved. The
gateway was reached through the campus tunnel. `gemini-3.7-flash` ran every
test again as the yardstick; its numbers reproduce the earlier studies (the
viva grade gap of the 2026-10-18 audit, 3% wrong assist diagnoses in the
2026-10-15 read), so the readings below compare with those.

1. **Quick check:** one request per feature per model — all answered, the
   cost header was present, no reply came near its token limit.
2. **Viva grading:** the 316 exam sessions that already have a reader grade
   (a grade a Claude reader wrote from the transcript before seeing the AI
   grade): 705 and 701 from the 2026-10-18 audit (143 each), 721 from the
   2026-10-28 Quiz 3 sample (30). Today's rubric context for all three models;
   12 sessions graded three times.
3. **Viva replies:** 40 points cut from real sessions (6 openings, 8 requests
   for the answer or a hint, 6 Thai replies, 6 natural endings, 14 others;
   20 exam, 20 practice); each model wrote the next examiner message. Three
   Claude readers judged the 120 replies blind against the conduct and
   briefing. 72 more openings checked the scenario-code copy mechanically.
   30 replies sent at the same instant per model, twice (22:40 and 22:50).
4. **Assist:** the 60 Quiz 2 requests of the 2026-10-15 head-to-head, answered
   by each model; nine Claude readers on the 2026-09-03 rubric, blind, each
   chunk mixing all three models and never two answers to one request.
5. **Grounding extraction:** five DS decks (the database's only grounding
   material is typed text); the share of each draft's code lines found in the
   deck's own text layer.

Gateway spend for all of it: US$19.48.

## Results

**Viva grading — points above the reader grade (average):**

| Model | All 316 | Q1 705 | Q2 701 | Q3 721 | >10 above | Rank agreement | Run-to-run (typical / largest) | s / grade | $ / grade |
|---|---|---|---|---|---|---|---|---|---|
| gemini-4-argon | **+5.6** | +2.7 | +9.0 | +3.0 | 20% | 0.97 | 1 / 9 | 5.6 | 0.017 |
| gemini-3.8-flash | +10.8 | +10.0 | +12.6 | +6.4 | 50% | 0.96 | 4 / 13 | 9.8 | 0.010 |
| gemini-3.7-flash | +14.5 | +12.2 | +17.8 | +10.1 | 66% | 0.96 | 2.5 / 11 | 7.2 | 0.009 |

No grade failed (0 of 1,020 calls needed the re-ask). No model graded more
than 10 points below a reader. On Quiz 3, whose exam overlay says the narrative
names only the topic, argon's narratives named `mLess` in 4 of 30 sessions,
3.7-flash's in 22 of 30.

**Viva replies — blind read, counts of 40:**

| | argon | 3.8-flash | 3.7-flash |
|---|---|---|---|
| Gives the answer away | 1 | 3 | 4 |
| Narrows it down too early | 13 | 7 | 5 |
| Explains after a failure | 0 | 1 | 3 |
| Accepts unchecked work | 2 | 7 | 6 |
| Ends with a plan step open | 1 | 4 | 6 |
| Leaves the plan | 3 | 8 | 8 |
| Two or more questions at once | 9 | 5 | 7 |
| Opening correct (of 6) | 5 | 3 | 2 |
| Wait median / 90% / slowest (s) | 4.9 / 20.8 / 44 | 6.7 / 13.4 / 40 | 4.3 / 9.4 / 11 |
| Opening median (s) | 20 | 12 | 9 |
| 30 at once: run 1 / run 2 slowest (s) | 37 / 9 | 19 / 13 | 189 / 523 |

One argon opening (problem 701) inserted a made-up line into the scenario's
class; the 72 further openings (12 with code per model) copied it exactly, as
did every flash opening. 3.7-flash left about a third of the simultaneous
replies waiting 50–60 s in both runs.

**Assist — blind read of 60 answers per model:**

| | argon | 3.8-flash | 3.7-flash | Opus (10-15 read) |
|---|---|---|---|---|
| Wrong diagnosis | 3% | 5% | 3% | 37% |
| Hands over the algorithm | 8% | 3% | 10% | |
| One issue only | 62% | 88% | 73% | |
| Wait median / 90% / worst (s) | 12.5 / 14.5 / 17 | 18.8 / 38 / 71 | 12.9 / 19 / 41 | 21 median |
| $ per answer | 0.025 | 0.015 | 0.012 | 0.049 (0.118 in Quiz 3) |

**Grounding extraction — code lines found in the deck:** argon 97 / 100 / 100 /
84 / 99% on the five decks; 3.8-flash 53 / 100 / 82 / 83 / 91%; 3.7-flash
67 / 72 / 74 / 85 / 99%. Argon took up to 86 s and $0.11 per deck; its
longest draft used 6,652 of the 8,192-token limit.

## Conclusions

- **Viva grading → argon.** Closest to the readers on every problem, the
  steadiest across runs, the fastest, and it keeps the exam overlay's
  narrative rule. Quiz 2 is still 9 points high. Grades of the remaining
  quizzes this semester will be stricter than Quizzes 1–3 were (dae accepted).
- **Grounding extraction → argon.**
- **Assist → argon in place of Opus;** 3.7-flash stays. Argon matches flash's
  accuracy at a quarter of Opus's Quiz 3 price and with the steadiest wait;
  it keeps to one issue less often.
- **Viva replies stay on 3.7-flash for now.** Argon is better on the audit
  faults (unchecked work, early endings, explaining after failure) but
  narrows the search more, bundles questions, opens in 20 s, altered the
  scenario code once, and its two simultaneous-load runs disagree.
- **3.8-flash beats neither.** Same token price as 3.7-flash, but more
  thinking makes each call 10–30% dearer and slower.

Applied as chula_cp 2273 (`config/llm.yml`), dae 2026-10-29.

## Limits

- Reader grades and blind reads are Claude's judgment (Sonnet readers), not a
  human's; 3.7-flash reproducing its earlier numbers shows the reads are
  consistent, not that they are right.
- The viva readers' packs omitted the platform's security directive, so
  alert judgments are approximate.
- The load runs were at night; exam-hour traffic was not measured.
- Only DS vivas of this semester were graded; no Algorithms vivas.
- Argon may be a preview model; Google can change it without notice.
