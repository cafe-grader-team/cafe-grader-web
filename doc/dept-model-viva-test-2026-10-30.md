# Department model viva test — qwen3.5, gemma-4-31b, glm-5.3, deepseek-v4.1-flash (2026-10-30)

> **Data and scripts for this study are not in this repository.** They contain
> student code and viva transcripts and live in the instructor's local
> `course-prep` repo, `dept-litellm-viva-2026-10-30/`. This document holds the
> method, the numbers and the conclusions only.

**Question.** The department now runs its own LiteLLM at `http://10.0.5.92:4000`
in front of four models: `qwen3.5` (DGX B200) and `gemma-4-31b` (A100 server),
which cost nothing to run, and `glm-5.3` and `deepseek-v4.1-flash` (Huawei
MaaS, paid). Could any of them take viva grading or viva replies, today run by
`gemini-4-argon` and `gemini-3.7-flash` on the Chula AI Gateway? dae expected
not, and asked how bad they are. Background: the multi-gateway design,
`docs/superpowers/specs/2026-10-30-multiple-ai-gateways-design.md`.

## Method

The same sessions and reply points as `doc/gateway-model-test-2026-10-29.md`,
so the numbers line up with argon and 3.7-flash without re-running them. Run
offline: the local production copy, the committed `Llm::VivaGradeAiGatewayAssist`
and `Llm::VivaTurnAiGatewayAssist` pointed at the department LiteLLM, the
payload production would send, through `execute_call` only, so nothing was
saved. Two departures, both what the design would do: qwen got
`max_tokens: 16384` (it thinks first, and 4096 can leave the answer empty), and
PDF parts are dropped (all four models refuse them). The viva problems used
carry no statement PDF, so no request lost anything.

1. **Quick check:** two grades and two replies per model.
2. **Viva grading:** the 316 exam sessions that have a reader grade (705 and
   701 from the 2026-10-18 audit, 721 from the 2026-10-28 Quiz 3 sample),
   12 of them graded three times. A reply that is not a grade is asked once
   more, as production does.
3. **Viva replies:** the 40 points cut from real sessions in the 10-29 test;
   each model wrote the next examiner message. 24 more openings per model
   (4 each on 693, 694, 695, 701, 705, 721) checked that the scenario's code
   is copied exactly. Three Claude readers judged deepseek's, gemma's and
   3.7-flash's 40 replies blind with the 10-29 reader instructions; the same
   3.7-flash replies the 10-29 readers judged were mixed in, which measures
   how much the readers themselves vary.
4. **30 replies at the same instant** per model (deepseek and gemma only; see
   Limits).

LiteLLM-price spend: US$26.68 — glm $17.26 and deepseek $1.58 are real
Huawei charges; qwen $5.91 and gemma $1.93 are the notional prices set in
LiteLLM for models that cost nothing to run. glm's timed-out calls are not in
these figures and may also have been charged.

## Results

**Viva grading — points above the reader grade (average):**

| Model | Graded | All | Q1 705 | Q2 701 | Q3 721 | >10 above / below | Rank agreement | Run-to-run (typical / largest) | s / grade (median / slowest) | $ / grade |
|---|---|---|---|---|---|---|---|---|---|---|
| deepseek-v4.1-flash | 316 | **+5.3** | +5.2 | +6.1 | +2.3 | 23% / 1% | 0.96 | 5.5 / 13 | 6.1 / 33 | 0.0037 |
| gemma-4-31b | 316 | +3.7 | +6.3 | +1.8 | +0.3 | 24% / 5% | 0.93 | 4 / 10 | 8.6 / 37 | (0.0043) |
| glm-5.3 | **304** | +5.8 | +6.9 | +4.8 | +4.4 | 27% / 1% | 0.97 | 3 / 7 | **123 / 600+** | 0.0446 |
| qwen3.5 | 315 | +10.2 | +10.9 | +9.6 | +9.5 | 51% / 0% | 0.93 | 8 / 13 | 24 / 168 | (0.0142) |
| gemini-4-argon (10-29) | 316 | +5.6 | +2.7 | +9.0 | +3.0 | 20% / 0% | 0.97 | 1 / 9 | 5.6 / 54 | 0.0168 |
| gemini-3.7-flash (10-29) | 316 | +14.5 | +12.2 | +17.8 | +10.1 | 66% / 0% | 0.96 | 2.5 / 11 | 7.2 / 15 | 0.0086 |

Prices in brackets are notional. Average distance from the reader, either way:
deepseek 7.2, gemma 8.0, glm 7.6, qwen 11.3, argon 6.6, 3.7-flash 14.6.
gemma's low average hides scatter: 5% of its grades are more than 10 below
the reader, and on 701 its rank agreement is 0.85. glm failed 17 of its 340
calls, all on 721: it thinks through about 15,000 tokens per grade there, and
each failed call ran past the 10-minute limit three times. qwen failed once
(no grade after 16,384 tokens).

**Viva replies — speed and breakage (40 replies, 24 extra openings):**

| | deepseek | gemma | glm | qwen | argon (10-29) | 3.7-flash (10-29) |
|---|---|---|---|---|---|---|
| Usable replies (of 40) | 40 | 40 | 39 | **36** | 40 | 40 |
| Wait median / 90% / slowest (s) | 3.4 / 9.4 / 15 | 10 / 36 / 99 | 33 / 130 / 169 | 21 / 77 / 199 | 4.9 / 20.8 / 44 | 4.3 / 9.4 / 11 |
| Opening median (s) | 5 | 32 | 77 | 38 | 20 | 9 |
| Openings copying the scenario code exactly | 24/24 | 24/24 | 24/24 | 23/24 | 24/24 (one altered among the 40 replies) | 24/24 |
| $ per reply | 0.0036 | (0.0047) | 0.027 | (0.015) | 0.013 | 0.0056 |

qwen's four broken replies: three empty after about 190 s of thinking that
used the whole 16,384-token limit, and one opening that looped on a Chinese
phrase for about 40,000 characters. glm overran the 4,096-token reply limit
in 31 of its 64 answers and timed out once (point 11, where qwen also came
back empty).

**Viva replies — blind read, counts of 40:**

| | deepseek | gemma | 3.7-flash | 3.7-flash, 10-29 readers |
|---|---|---|---|---|
| Narrows it down / gives the answer | 6 / 5 | 8 / 4 | 5 / 4 | 5 / 4 |
| "Correct" / "not quite" while still assessing | **11** | 7 | 4 | 2 |
| Thai reply where 693 requires English | **4** | **4** | 0 | — |
| Leaves the plan | 5 | 6 | 13 | 8 |
| Ends with a plan step open | 1 | 3 | 4 | 6 |
| Two or more questions at once | 4 | 8 | 6 | 7 |
| Technically wrong statement | 1 | 2 | 0 | 0 |
| Alert without cause | 2 | 0 | 1 | 1 |
| Opening correct (of 6) | 1 | 0 | 1 | 2 |
| Reply with no fault | 13 | 10 | 13 | — |

The two sets of readers differ by up to five replies on the same 3.7-flash
text (leaves the plan: 13 against 8), so only the larger gaps count:
deepseek's running verdicts, two of which grew into long Thai closing
summaries that gave the answers away, and both models answering in Thai.
This round's readers failed nearly every opening over a missing title line or
a part-translated task list; that is a reader difference, not a model one.

**30 replies at the same instant:**

| | Answered | Wait median / 90% / slowest (s) |
|---|---|---|
| deepseek-v4.1-flash | **21 of 30** — 9 refused, HTTP 429 "the rate limit is 4 per second" | 4.4 / 11.2 / 12.3 |
| gemma-4-31b | 30 of 30 | 32.8 / 71.9 / 82.8 |
| deepseek-v4.1-flash, after the LiteLLM change (2026-10-31) | **28 of 30** — 2 still refused, after about 19 s | 8.4 / 14.4 / 15.8 |
| same, 8 at once ×3 and 12 at once ×2 (Quiz 3's real peak was 8) | **48 of 48** | 2.9–5.5 median per run; slowest 17.2 |

Before the change each refusal came back after about 5.5 s: LiteLLM's router
was already retrying twice ("Number of retries" 2, "Retry after" 0), too
quickly to get past the limit. dae set "Number of retries" 4 and "Retry after"
1 s in the LiteLLM admin UI (Router Settings; the UI has no per-error retry
setting, so this applies to every model and every error).

For scale, from `viva_turns.llm_started_at` / `llm_latency_ms`: in Quiz 3
(721, 964 model calls) at most 8 calls were in flight at once and at most 6
started within one second; 2 seconds had more than 4. In Quiz 2 (701) the
peaks were 5 and 4. The grader does not retry a 429, so deepseek would have
failed about two student messages in Quiz 3. A model three times slower than
3.7-flash keeps about three times as many calls open, so gemma would see
roughly this test's load during an exam.

## Conclusions

- **qwen3.5 and glm-5.3: not for viva.** qwen grades 10 points high and broke
  4 of 40 replies; glm grades well but takes two minutes a grade, fails on
  long problems, ignores the reply limit and is the dearest model tested.
- **deepseek-v4.1-flash is the only candidate.** Grades as close to the
  readers as argon (+5.3 against +5.6, rank agreement 0.96 against 0.97, but
  less steady between runs: typical 5.5 against 1), replies as fast as
  3.7-flash, question quality level with 3.7-flash, and about a quarter of
  argon's price per call. Before it could run vivas: the 429 retry (design
  §4.10, plus a retry in the department LiteLLM), and something that keeps
  it in English and stops its running verdicts.
- **gemma-4-31b** asks about as well and is free, but under exam load a
  typical reply takes about 30 s, and its grades scatter.
- **Cost is not a reason to switch.** Quiz 3 as run today (3.7-flash replies,
  argon grades, 964 replies and 109 grades) costs about $7 at gateway
  prices; all-deepseek about $4.
- No configuration changed. The test surfaced a briefing error on problem 693
  (Viva-History 2026-10-31).

## Limits

- Reader grades and blind reads are Claude's judgment, not a human's. This
  round's readers were not pinned to the 10-29 readers' model (Sonnet); the
  3.7-flash column read by both shows the size of the difference.
- deepseek's and gemma's replies were read against 3.7-flash only; argon's
  reply counts come from the 10-29 readers and are not in the blind table.
- qwen and glm were left out of the 30-at-once test: both were already ruled
  out, and qwen's server also carries the cp-api LINE bot.
- Load runs were at night; exam-hour traffic on the Huawei and DGX side was
  not measured. Huawei's 4-per-second limit may be per account, so other apps
  on the same account share it.
- Only DS vivas of this semester; no Algorithms vivas.
