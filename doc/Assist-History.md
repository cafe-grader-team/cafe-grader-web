# Submission Assist ("Codey") — Change History

What we changed in the AI helper on coding submissions, why, and how it turned
out. Newest first. This is the *timeline*; the study that measures the feature
is `doc/assist-corpus-eval-2026-09-03.md`; the prompt text itself is versioned
in the local `course-prep` hg repo under `assist/`.

**How to add an entry** (rule in `CLAUDE.md` → "Viva & Assist Live Docs"): any
commit that changes assist behavior, the payload sent to the model, the prompt
text (the `codey-*` tags), the models or providers in the picker, or the
price/access policy adds an entry here *in the same commit*, shaped **Problem
observed → Change → Outcome / status**, with refs. Prompt edits cite
`course-prep rev N`. When an entry supersedes an earlier one, mark the old one
`SUPERSEDED YYYY-MM-DD by …`; never delete. Rev numbers are local hg revs of
`~/cafe-grader/web` (master unless marked `chula_cp`).

## Where the record lives

- **This repo (mirrored to GitHub):** the timeline (this file), the studies
  (`doc/assist-corpus-eval-*.md`), the platform code and its CHANGELOG. Nothing
  here may contain student code, tutor answers to real students, or the prompt
  text itself.
- **`course-prep` — a Mercurial repo on the instructor's workstation, not
  published anywhere:** path `~/cafe-grader/course-prep` on `dae-amd-2024`
  (WSL2 Ubuntu 24.04), started 2026-09-02; it holds exam papers and model
  answers, so it has no public remote by rule. Since 2026-09-04 it is mirrored
  to a **private** GitLab project (`gitlab.nattee.net/nattee/course-prep`, via
  hg-git; `hg push gitlab` after every commit there); before that the only copy
  was that disk. Contents for this feature: `assist/codey-core.md` and
  `assist/codey-thai.md` (the live prompt tags, versioned), the originals they
  replaced, and `assist/eval-<date>/` — every evaluation's data and scripts:
  the answers read, the readers' and judges' scores, the whole-corpus frames,
  the blind human-read form and its answers, UI screenshots. Cite
  `course-prep rev N` from entries here. Anyone reading this on GitHub or the
  wiki who needs the underlying data asks the instructor.
- **Production database (`grader` on 10.0.5.50):** the primary source — every
  request and answer is a `comments` row (`kind: llm_assist`), with the prompt
  tags in `tags`. Everything above is derived from it and can be regenerated
  with the scripts in `assist/eval-<date>/` against a fresh copy (the dump
  script is `~/dump_grader.sh` on the host).

## What the feature is

A student who is stuck on a graded submission can press **Get** under "AI help
by `<model>`" on the submission page. The platform sends the model a system
prompt (the `codey-*` tags), the statement PDF, the manager files, the student's
source and its verdict — since 2026-09-03 also the compiler output, the real
per-testcase table and the previous answer with a diff — and stores the reply
as a comment on the submission. The request costs the student **10 points** of
the problem's full score (the "reduced full score" mechanic: final score =
min(best score, 100 − penalties), floored at 0 since 2026-09-03). It is on
only when the site switch `system.llm_assist` is on, and in contest mode only
for contest problems flagged `allow_llm`. Only the submission's owner (or an
admin) may request it (since 2026-09-03); an admin's request costs the
student nothing (since 2026-09-09).

## Eras at a glance

| # | Era | Dates | Characterization |
|---|-----|-------|------------------|
| 6 | Review, hardening, rebuild | 2026-09-03 → 09-09 | Code review found seven defects (any user could charge any student; index-addressed model; negative scores; raw-HTML answers); payload rebuilt around what the grader knows; picker guards + spend cap; dollar/token accounting; two prompt copies collapsed into `codey-core` + `codey-thai`; first corpus evaluation (291 answers read); this document. Follow-ups 09-09: an admin's request is free for the student; per-model cost on the stat pages; Genie models off the picker by default. |
| 5 | New providers, new models | 2026-07-30 → 08-30 | Self-hosted DGX provider; Genie roster refresh makes gemini-3.1-pro the default and *un-breaks* Claude-Sonnet (silently downgraded since Feb); Chula AI Gateway family adds claude-opus-4-5 and gemini-3.7-flash to the picker; gateway-reported cost. |
| 4 | Tag taxonomy | 2026-07-20 → 07-21 | Viva moves off `llm_prompt`; the kind now means exactly "AI-helper system prompt"; the generic tag picker keeps offering it (D6 amendment). |
| 3 | Refactor | 2026-05-07 → 05-19 | `Llm::Request` hierarchy; comment-assembly lifted from `GenieAssist` into `CommentAssist`; the score-penalty semantics regress and are restored the same day; `preview` tooling; `llm.yml.SAMPLE`. |
| 2 | Two semesters live | 2025-07-23 → 2026-05 | ~2,370 requests each semester on gemini-2.5-pro + Claude-3.5-Sonnet via ChulaGenie; managers added to the payload; contest score views show the penalty; Claude path breaks on PDFs (Feb–Mar 2026) and the Genie rename leaves the picker effectively single-model from Feb 14. Prompt text frozen. |
| 1 | Birth | 2025-06-29 → 07-17 | Comments gain LLM columns; `GenieAssist`; "acquire" confirm dialog with the 10-point price; per-model provider map in `llm.yml`; site switch; contest `allow_llm`; tags gain `params` and the `llm_prompt` kind — the prompt moves out of code into a tag. |

## Lineages (the same story told per thread)

- **Models actually running in prod:** gemini-2.5-pro + Claude-3.5-Sonnet via ChulaGenie (2025-07-23 →). Claude-3.5-Sonnet: 74 HTTP-400s Feb–Mar 2026 (Anthropic rejects the PDF sent as `image_url`), last answer 2026-03-03. Config renamed it `Claude-Sonnet` on 2026-02-14 (rev 1498) but the class's allowlist still said `Claude-3.5-Sonnet`, so every Claude request was **silently served by gemini-2.5-pro until 2026-08-23** (rev 2006). gemini-2.5-pro last answer 2026-08-23 (dropped from the picker, not from the relay — `Llm::GenieAssist.list_model` still lists it on 2026-09-03; relay retirement expected ~2026-10). Then: gemini-3.1-pro + Claude-Sonnet (Genie, 08-24 →), claude-opus-4-5 (Gateway, 08-27 →), gemini-3.7-flash (Gateway, 08-28 →). Since 2026-08-01 no request has errored. → Genie models (gemini-3.1-pro, Claude-Sonnet) withdrawn from the picker by default, relay kept as a backup (config chula_cp 2118, 2026-09-09; live 2026-09-10 15:51). → Picker kept as claude-opus-4-5 + gemini-3.7-flash after the Gateway read (dae, 2026-10-28). → gemini-4-argon (Gateway) replaces Opus in the picker and becomes the default; Opus stays configured as a backup (config chula_cp 2273, 2026-10-29, from its deploy).
- **Prompt storage and text:** hard-coded in `GenieAssist` (06-29) → `llm_prompt` tags per problem (07-17); two full copies `AI-AL` (239 problems) and `AI-DS` (45), identical apart from AL's Thai-translation appendix (present by 2026-03-04 at the latest); text otherwise unchanged for the feature's life → `codey-core` + one-line `codey-thai` (2026-09-03, `course-prep` rev 3) → evaluation-driven rewrite `codey-core` v2.2 live 2026-09-05 (`course-prep` rev 13; rev 4 tested offline, +1 sentence from the follow-up).
- **Payload:** system prompt + statement PDF + source + verdict string (07-17) → + manager files with a do-not-reveal instruction (08-23) → + compiler output on compile errors, per-testcase table (group, verdict, time, memory, score, limits), previous answer + line diff on repeat requests (2026-09-03, rev 2089; on prod 2026-09-05 with chula_cp 2112). The prompt's "How to Map" section went with the rev 13 text the same day. → + a fixed boundary line after the problem material, carrying a prompt-cache marker on Gateway requests; managers sorted by file name (2026-10-12, rev 2264).
- **Price and score policy:** 10 points per request, a constant in code, stated in the confirm dialog (07-11) → the same 10 as a site setting `system.llm_assist_cost` (2026-09-03, rev 2100); contest views show `final_score = min(max, 100 − llm − hints)` (09-14, summation fixed 11-25) → floored at 0 (2026-09-03, rev 2085; 10 student–problem pairs had gone negative, worst −360) → requests refused while one is running, when that model already answered, at full score, and once 100 points are spent on the problem (rev 2090) → an admin's request on a student's submission is charged 0 (2026-09-09, rev 2116).
- **Access:** site switch + contest `allow_llm` + tag present (07-10/11) → + owner-or-admin (2026-09-03, rev 2084; 11 historical requests were made by someone other than the owner, who paid).
- **Accounting:** score penalty only (`comments.cost`) → `llm_cost`, `prompt_tokens`, `completion_tokens` + backfill task (rev 2089) → shown per model on the user and problem stat pages (2026-09-09, rev 2117).
- **Measurement:** none → next-submission outcome metric + mechanical checks + 291-answer read (2026-09-03) → offline old-vs-new prompt test, 100 inputs × 3 arms, blind-read (2026-09-04, Part 4 of the evaluation doc).

## Numbers for reporting (production, as of 2026-09-03 11:44)

| | |
|---|---|
| Requests | 5,264 (answered 4,787 · errored 80 · stuck "processing" 397, all Aug–Sep 2025) |
| Students who used it | 313 |
| Submissions / problems touched | 4,816 / 240 |
| By semester | 1/2568 (Aug–Dec 2025) 2,371 · 2/2568 (Jan–May 2026) 2,349 · summer 24 · 1/2569 (Aug 1 – Sep 3, 2026) 515 |
| Peak month | April 2026, 856 |
| By course (problem-name prefix) | `d*` Data Structures 2,341 · `a*` Algorithms 1,989 · `ex*` exercises 235 · `da*` 163 · `ds*` 85 |
| Repeat requests | 44% of answers were the student's 2nd+ request on that problem; max 46 on one problem; 316 students, median 9 requests each, p90 36, max 131; top tenth of students made 38% of requests |
| Score penalty charged | 47,020 points over 2,699 student–problem pairs |
| Tokens (gemini-2.5-pro, 4,206 answers) | 18.1M prompt · 23.1M completion (avg 5,500 completion — a reasoning model) |
| Tokens (Claude-3.5-Sonnet, 699) | 6.7M prompt · 0.33M completion |
| Contest use | `allow_llm` on in 12 of 39 contests |
| Effectiveness (pre-2089 payload) | paired, same student & problem: the step before the first assist improved 27%, the assisted step 38%; 37% reach full score within 3 submissions, 63% ever; 14% never resubmit. Compile errors worst (next↑ 25%), repeat requests worse than first. Aug 2026 head-to-head on 22 shared problems: current models next↑ 50% vs gemini-2.5-pro 38% (n=105). Never-asked students are not a valid baseline. |
| Quality (291 read) | hard rules hold (1% write code, 3% name a technique); 64% state the fix, 9% describe the algorithm; gemini-3.1-pro 0% wrong diagnoses (n=90), Claude-Sonnet 20% (n=40); details in the evaluation doc |

---

## Entries

### 2026-11-24 — An AI answer opened in a new tab shows as a page
**platform code (display only)** · master 2337
- **Problem observed:** "View" on an AI answer opens a popup. Opened in a new tab (or clicked before the page finished loading) it was a plain page request, which had no view: a server error, 9 times on cedt during the 2026-11-21 exam.
- **Change:** a page view of the same answer (same sanitizing, same trusted header). The header's code-highlight call waits for the page to load when highlight.js isn't there yet. Payload, prompt, price and access unchanged.
- **Outcome / status:** tests pass (`bin/rails check` 1659 tests), including a browser test of both the page and the popup; committed, not yet pushed or deployed.

### 2026-11-21 — The 100-point spend stop becomes a setting; contests get a deduction cap
**platform code (price / access policy)** · master 2332; spec `docs/superpowers/specs/2026-11-21-deduction-cap-spending-limit-design.md`
- **Problem observed:** on 2026-11-21 a student reached the fixed 100 points of AI help on one problem and the instructor wanted to allow more, but `Submission::LLM_ASSIST_FULL_SCORE` refused it. Separately, instructors often announce "hints and AI help take at most N points per problem" and applied it by hand after the contest.
- **Change:** the **spending limit** (the most points of AI help one student may spend on one problem before Get is refused; hints never counted) is now the site setting `system.llm_assist_spending_limit` (100, created by a data migration) with a per-contest override `contests.assist_spending_limit`; with two running contests on one problem the larger wins. The refusal reads "already spent N of the M points of AI help allowed on this problem", and a limit of 0 reads "no AI help is allowed on this problem". The **deduction cap** (`contests.deduction_cap`) bounds what hints + AI help take off the full score in that contest's reports and in the student's problem list during it. The AI confirm box now also states what the student has lost so far on the problem, how much of this request counts under the cap, and the spending limit. Payload and prompt unchanged.
- **Outcome / status:** tests pass (`bin/rails check` 1637 tests); committed and pushed 2026-11-22; deployed fleet-wide 2026-11-23, verified 2026-11-24.

### 2026-11-19 — The prompt-cache marker goes to Claude models only (Gemini refused problems with little material)
**platform code (payload)** · master 2297; found 2026-11-15 on the local database copy
- **Problem observed:** the marker of rev 2264 went to every Gateway model. Through the Gateway's LiteLLM a Gemini model does not ignore it, as the 2026-10-12 entry said: the key asks for Gemini's explicit cache, which refuses material under 4,096 tokens — HTTP 400, "The cached content is of 2060 tokens. The minimum token count to start explicit caching is 4096". Reproduced on the local database copy with comment 7411 (problem 723, no statement PDF on the copy): 400 for gemini-4-argon and gemini-3.7-flash with the marker, 200 for both with `prompt_cache: false`; gemini-4-hydrogen also answered 400. Requests whose material includes a statement PDF pass (all 200 inputs of the 2026-11-15 model test), which is why the 2026-10-12 test on problem 717 saw no error. gemini-4-argon has been the assist default since 2026-10-29, so once 2264 was deployed every assist request on such a problem would have failed. Never in production: 4.7.3 has no marker.
- **Change:** `AiGatewayAssist#prompt_cache_marker` adds the marker only when the model name contains "claude"; every other model gets the boundary line without it. `prompt_cache: false` still turns it off for all models. New test: a Gemini model on a problem with no statement PDF gets no marker (it fails without the fix).
- **Outcome / status:** tests pass; not deployed. The cp-grader picker now offers only Gemini models (gemini-4-argon, gemini-3.7-flash; chula_cp `config/llm.yml`), so caching takes effect there only if a Claude model returns to the picker. The 2026-10-12 entry's re-measurement applies to Claude requests only.

### 2026-11-03 — cedt and comprog get a working Gateway key and the cp-grader prompt
**access (credentials) + prompt text (data on two hosts)** · no code change; prod data on cedt-grader 10.0.5.80 and comprog-grader 10.0.5.52
- **Problem observed:** cedt and comprog had no Chula AI Gateway key in their Rails credentials (only the old Genie key), so every assist request after the 2026-09-09 Genie withdrawal failed with `ConfigError: llm.ai_gateway.api_key is missing`. cedt had 20 failures and no success after 2026-09-08. comprog had no requests since 2025-08. Both hosts also still ran the pre-2026-09-05 prompt: cedt's `AI-DS` / `AI-AL` (one 2025-11-25 text on 136 problems) and comprog's `AI-CP` (a Python-tutor prompt answering in Thai only, on 2 problems). Those prompts were written before the payload carried the per-test results table and the previous answer.
- **Change:** 10.0.5.50's Gateway key was copied into both hosts' credentials and both hosts were restarted (cedt 11:40, comprog 11:46 +07). `codey-core` + `codey-thai` were copied byte-identical from 10.0.5.50 and put on every problem that carried an old prompt: 136 on cedt, 2 on comprog. comprog therefore now answers in English followed by a Thai translation, where it used to answer in Thai only. The old tags are detached. cedt's are renamed `ARCHIVED-delete-soon-*` and kept as a backup. comprog's is renamed `PHASING-OUT-AI-CP` and marked do-not-delete: it is the Python-course reference from which a comprog lecturer may adapt `codey-core` into a `codey-python` tag (dae). Problems that had no prompt stay without one, e.g. cedt's 104, DigLo and DB courses, except the two visible problems of cedt's current 2110328 group `328-2026a-student` that lacked one: `ds01_pair_sum` and `a66_q1a_day_cover` also got `codey-core` + `codey-thai`, so all 132 of that group's problems have it.
- **Outcome / status:** live calls to argon and 3.7-flash were checked from each host; the tag texts were checked equal to 10.0.5.50. The cedt archived tags are to be deleted once the new prompt has run there for a while; `PHASING-OUT-AI-CP` goes only after a `codey-python` exists.

### 2026-10-29 — gemini-4-argon replaces Opus in the picker and becomes the default
**model change (deployment config) + study** · chula_cp 2273 (`config/llm.yml`); study `doc/gateway-model-test-2026-10-29.md`, data and report in course-prep `gateway-argon-2026-10-29/`
- **Problem observed:** students pick claude-opus-4-5 for 83% of requests (Quiz 3), yet it gave a wrong diagnosis on 37% of the 60 Quiz 2 head-to-head inputs (2026-10-15) and cost USD 0.118 per request in Quiz 3. On 2026-10-29 the Gateway began serving `gemini-4-argon` and `gemini-3.8-flash`.
- **Change:** the same 60 inputs answered offline by argon, 3.8-flash and 3.7-flash with today's payload, read blind by nine readers on the 2026-09-03 rubric (each chunk mixing the three models). Wrong diagnoses argon 3%, 3.8-flash 5%, 3.7-flash 3% (the control matches its 3% of 10-15); hands over the algorithm 8 / 3 / 10%; one issue only 62 / 88 / 73%; wait median 12.5 / 18.8 / 12.9 s with the worst at 17 / 71 / 41 s; USD 0.025 / 0.015 / 0.012 per answer. dae 2026-10-29: the picker offers gemini-4-argon and gemini-3.7-flash; claude-opus-4-5 leaves it but stays in the `ai_gateway` roster as a backup (add it back to the `AiGatewayAssist:` line and restart); argon is also the `assist` default.
- **Outcome / status:** committed and pushed (chula_cp 2273); live from the cp-grader deploy. Supersedes the 2026-10-28 "keep both" decision. Next quiz: measure argon's wait under exam load from production (`comments.llm_latency_ms`) — the simultaneous-load runs at night disagreed — and argon's one-issue rate is the thing to watch in the next read.

### 2026-10-28 — DS Quiz 3 exam usage measured; picker kept as it is
**analysis + decision, no code change** · course-prep `data-structures/viva/quiz-2569-3-postexam-2026-10-28/` (`report.html` §4, `tools/assist_stats.py`); local prod copy refreshed 2026-10-28 22:34
- **Problem observed:** DS Quiz 3 (contest 47 `d69_q3`, 2026-10-21) was the first exam after the Gateway read (2026-10-13) and the prompt-caching change (master 2264). Production still ran 4.7.3, so caching was not live.
- **Change:** none to the platform. Measured the quiz with the Quiz 1 method (`doc/exam-postmortem-2026-09-09-d69_q1.md` §F8): 362 requests by 107 students on 723/724/725, 3,620 penalty points, USD 36.23. claude-opus-4-5 299 requests (83%, up from 68% in Quiz 2), USD 35.41 = USD 0.118 per request (Quiz 2: 0.103); gemini-3.7-flash 63, USD 0.82. Cache reads 7,112 tokens in all — none from the caching code. Median wait 24 s, 95% under 72 s; the queue backed up at 10:25 (a provider slowdown that also hit the viva) and in the last five minutes (46 requests). After a request 86% resubmitted, 56% beat their earlier best, 20% reached 100 (Opus 57%, flash 51% — who asks, not answer quality). 89% of requests came from a score under 25. Per student and problem (157 pairs): 51 gained more than the penalty, 6 broke even, 100 ended worse off (Quiz 1: 97 of 133). 27 of the 76 requests in the last ten minutes had no later submission. Answers were not read for quality this time.
- **Outcome / status:** *(SUPERSEDED 2026-10-29 by the Gateway model test entry: Opus left the picker for gemini-4-argon.)* dae decided to keep both models in the picker as they are (the 2026-10-13 study recommended flash only). Found: two requests made after the quiz on quiz submissions were charged against the quiz score (`Contest#score_report` counts every assist on a contest submission) — no score changed this time; filed in `doc/backlog.md` (Submission assist → Scoring). Open: re-measure caching after the next deploy that carries master 2264.

### 2026-10-13 — First read of the Gateway models' answers: Opus misdiagnoses, flash does not
**study** · `doc/assist-gateway-read-2026-10-13.md`; data + scripts `course-prep` rev 26 (`assist/eval-2026-10-13/`)
- **Problem observed:** since 2026-09-10 the picker offers only claude-opus-4-5 and gemini-3.7-flash (Gateway), and nobody had read their answers (backlog "Gateway models unread"). Students pick Opus about two to one.
- **Change:** 99 production answers from 2026-09-06 on (60 Opus, 39 flash), cell mix copied from the 2026-09-04 offline test, read blind by 6 Claude readers on Part 1's rubric. Every wrong-diagnosis call was then checked by hand.
- **Outcome / status:**
  - **Wrong diagnoses:** Opus 12 of 60 by the readers; flash 0 of 39. On the 18 problems both models answered, 7 of 38 against 0 of 37.
  - **Hard check (2026-10-14, `course-prep` rev 27):** the students' code was run on the real tests three ways — unchanged, changed as the tutor said, and changed at the reader's named cause. For all 8 Opus calls that could run, following the tutor fixed nothing: 7 changed no test at all, and the eighth passed 2 of its 4 failing tests by side effect. Fixing the reader's cause made the failing tests pass. All 5 flash diagnoses that were run named a real cause.
  - **One issue only:** Opus 48%, flash 82%.
  - **The same for both:** stating the fix (about 88%), handing over the algorithm (5% each), and no code.
  - **Flash's weak spot:** 5 of 39 diagnoses rest on header files the material lacks.
  - **What students did next** (all 894 answers since 09-06): no difference — improved 39% vs 43%, worse 12% each.
  - **Price:** flash costs about a ninth as much ($0.012 vs $0.103 per answer).
  - **Opus with thinking (2026-10-15, `course-prep` rev 28):** the same 60 inputs were answered again offline with extended thinking (budget 4,096) and read blind with 20 anchors from the first read. The new readers agreed with the first read on 19 of the 20 anchors.
    - **Wrong diagnoses:** 20% → 8% (5 of 60). 9 of the 12 originally wrong inputs are now right; 2 right ones became wrong.
    - **Hard check:** on the 8 runnable inputs where plain Opus was wrong, the thinking answer names the cause that fixes the tests in 5 and half of it in 1.
    - **Other measures:** one issue 48% → 58%; the median answer took 39 s (22 s without thinking); about $0.11 per answer with caching.
    - **Against flash:** still behind (0 wrong, 82% one issue, 12 s).
    - **New option (e):** keep Opus but turn thinking on, which needs a small master change. The study still recommends (b).
  - **Quiz 2 head-to-head (2026-10-15, `course-prep` revs 29–31):** asked for by dae — this year's exam content only, every model on the same inputs. 60 real requests from the three non-viva `d69_q2` problems were answered offline by flash, Opus as in production and Opus with thinking, then read blind by 9 readers.
    - **Wrong diagnoses:** flash 3%, Opus 37%, Opus with thinking 12%. Comparing the same inputs, Opus was wrong where flash was right 21 times and the reverse happened once; thinking Opus against flash was 6 to 1, which this sample cannot settle.
    - **Hard check:** most of plain Opus's errors are on the stack time-limit problem. It blamed the per-element copy, where counting the grader's expensive copies shows the cost is growing the stack one element at a time (12.7 million copies against 4.5 million). Its suggested fixes crash, save nothing, or are impossible within the problem.
    - **Time and price per answer:** flash 16 s and $0.011; Opus 21 s and $0.049; thinking Opus 51 s and $0.10. One thinking request returned an empty reply.
    - **Recommendation now:** (b) flash only; (a) + (e) if a Claude choice must stay; (c) is ruled out.
  - **Open decision (dae):** (a) list flash first, (b) take Opus out of the picker and keep it as a backup, as was done with Genie on 09-09, or (c) leave as is. The study recommends (b). **DECIDED 2026-10-28 (dae): keep both as they are** — see the 2026-10-28 entry. *SUPERSEDED 2026-10-29: Opus out of the picker (option (b)), replaced by gemini-4-argon — see the 2026-10-29 entry.*

### 2026-10-12 — Prompt caching on the problem material (Claude via the Gateway)
**platform code + measurement** · master 2264; live tests 2026-10-09 and 2026-10-12 through the Chula AI Gateway (throwaway scripts, not kept)
- **Problem observed:** claude-opus-4-5 was about 94% of the Gateway assist spend (616 requests, $55.9 from 2026-09-05 to 10-07), and exams concentrate it: Quiz 2 (`d69_q2`, 2026-10-07) cost $22.40 for 218 Opus requests. Most of each request is the same for every student on a problem: the `codey-*` tags, the statement PDF and the managers, an estimated 9.7k–15.4k tokens, about 85% of the input. None of it was reused: 0 cache reads on Opus, and 1 automatic reuse in 286 gemini-3.7-flash requests. In Quiz 2, 94% of Opus requests came within 5 minutes of the previous request on the same problem and 99% within 60 minutes; in normal weeks the figures are 52% and 65%. The 5-minute storage option is the cheaper one in both cases.
- **Change:** `CommentAssist#build_content_array` adds a fixed part, `PROBLEM_MATERIAL_END` ("End of the problem material. The student's work follows."), right after the managers, or after the PDF when there are no managers. `AiGatewayAssist#prompt_cache_marker` adds `cache_control: {type: 'ephemeral'}` to that part, so Claude keeps everything up to it (system message first) for 5 minutes. The grading table, the previous answer and the student's code come after it and are never stored. The marker is on unless the `ai_gateway:` block of `llm.yml` sets `prompt_cache: false`; other providers get the line without the marker. The managers are now sorted by file name, because a stored copy is reused only when everything before the marker is byte-identical.
- **Outcome / status:** measured 2026-10-09 on problem 717 (`d69_q2a_vector_find`) with two students' Quiz 2 requests. The first request stored 14,985 of 18,203 tokens (82%) for $0.127. The second student's request reused them: $0.054, against $0.126 for the same request without the marker. The Gateway's cost header already charges the discounted price, and `prompt_tokens` still counts the full input. gemini-3.7-flash accepts the marker and ignores it (no error, same cost). *(Corrected 2026-11-19: true only for material above Gemini's 4,096-token explicit-cache minimum; below it every Gemini request failed, and the marker now goes to Claude models only — see the 2026-11-19 entry.)* Speed: reading the input took 2.2 s without the stored copy and 1.0 s with it (5 runs each, answer cut to 5 tokens); the storing request took 3.0 s. Across 398 Opus answers, each extra 100 output tokens adds about 1.45 s and input size has no measurable effect, so the saving is about 1 s of the median 22 s wait. A changed PDF, managers file or tag simply misses once and stores the new version, so answers never use old material. Expected effect: an exam's Opus bill about halves. On 2026-10-12 the committed code itself was tested live (`AiGatewayAssist` through `execute_call`, no comment row written) with the same two students. The first request stored 14,985 tokens ($0.123); the second reused them ($0.055). Gateway quota used for all the tests: about $1.20. The Gateway API accepts only university-network addresses, so the tests ran through an ssh tunnel via 10.0.5.59. Not deployed; it takes effect with the next chula_cp merge and deploy, with no config change needed there. Re-measure after the next exam: every stored `llm_response` carries `cache_creation_input_tokens` and `cache_read_input_tokens`. Compare the mean Opus `llm_cost` with Quiz 2's $0.103 per request.

### 2026-09-12 — Quiz 1 exam usage measured: 260 requests, most students ended worse off
**analysis only, no code change** · `doc/exam-postmortem-2026-09-09-d69_q1.md` §F8
- **Problem observed:** during `d69_q1` (2026-09-09) 109 students made 260 assist requests (opus 82, gemini-3.1-pro 77, Claude-Sonnet 53, flash 48); 74% resubmitted afterwards, 36–50% improved by model, 2–13% reached 100. Of 133 student-problem pairs 97 ended worse off (penalty > gain). Requests queued behind viva turns on the shared 3-thread worker: mean wait 195 s, p95 457 s; 58 of the 75 requests in the last ten minutes got no follow-up submission.
- **Change:** SHIPPED on master (revs 2134–2143): assists now have a worker of their own (viva jobs moved to a dedicated `viva` queue, 2137); per-call timing on comments (`llm_started_at`/`llm_latency_ms`, 2136); and a contest AI-usage report showing assist volume, cost, per-model breakdown and response-time percentiles (2140–2141). Deployed with chula_cp 2158 — verified live on cp-grader 2026-09-21 and ise-grader 2026-09-22 (`hg id` on the hosts); other hosts unverified.
- **Outcome / status:** open; numbers not yet in the "Numbers for reporting" table.

### 2026-09-10 — Follow-ups live on production; historical rows cleaned up
**deployment + data** · chula_cp 2123 deployed 15:51 by dae via the GitLab pipeline (web_check, then the whole matrix); `~/cafe-grader/assist-cleanup-2026-09-09.rb` run by dae 17:08–17:19 (report, then one step at a time)
- **Problem observed:** the 2026-09-09 follow-ups (admin requests free for the student, per-model cost on the stat pages, Genie off the picker) were committed but not live; production still carried 397 requests stuck in `processing` since Aug–Sep 2025, 5,184 answers without token counts, and the dead `AI_viva` tag (#36, `llm_prompt` on `viva_test` 670 and `a68_mv_relay` 671).
- **Change:** deploy of chula_cp 2123 (also carries the `jobs` index, rev 2115); then `STEP=stuck` marked the 397 rows `error` "Assistant Error (abandoned)"; `STEP=backfill` copied token counts onto all 5,184 rows; `STEP=ai_viva` printed the tag text and deleted the tag and its two problem links.
- **Outcome / status:** picker on production = `claude-opus-4-5`, `gemini-3.7-flash`; 0 requests in `processing`; tokens on all 5,787 answers; `llm_prompt` tags = `codey-core`, `codey-thai`; 262 answers since 2026-09-05 carry a dollar figure, so the new stat tables show real costs from day one. Usage 2026-09-05 → 09-10 by model: gemini-3.1-pro 231, claude-opus-4-5 179, Claude-Sonnet 132, gemini-3.7-flash 88 — the students' most-used model is the one the Genie switch-off withdrew, which makes the Gemini Pro request to OIT (backlog) a real gap, not a nicety.

### 2026-09-09 — Decisions: Genie models off the picker by default (relay kept as a backup); `codey-thai` stays
**deployment config + decision** · chula_cp 2118 (config), master 2119 (this entry, backlog)
- **Problem observed:** the 2026-09-03 evaluation left two deployment decisions open — Claude-Sonnet via Genie was the least accurate model (8/40 wrong diagnoses, 6/40 hand-overs; gemini-3.1-pro 0/90), and the Thai appendix doubles the visible output on the 239 Algorithms problems.
- **Change:** dae 2026-09-09: (1) OIT says the ChulaGenie relay will rotate out soon — keep `GenieAssist` as a backup but do not offer its models by default; the registration line in chula_cp's `config/llm.yml` is commented out with the re-enable recipe (uncomment + restart), the classes are untouched. On deploy the "AI help by" block offers claude-opus-4-5 and gemini-3.7-flash (Gateway) only. (2) `codey-thai` stays as is — Algorithms students keep the English + Thai answer.
- **Outcome / status:** took effect with the 2026-09-10 15:51 deploy (chula_cp 2123). Recorded concern: gemini-3.1-pro leaves with the relay, and neither Gateway model has been read for quality yet — backlog: read a sample of each, ask OIT for a Gemini Pro model on the Gateway.

### 2026-09-09 — Stat pages show the per-model cost of AI assistance
**platform code** · master 2117
- **Problem observed:** `llm_cost`, `prompt_tokens` and `completion_tokens` have been recorded since rev 2089 (on prod since 2026-09-05) but appeared nowhere; the only visible figure was the score penalty, and the user stat card's "AI Assist" count went by who pressed Get, not by the student charged.
- **Change:** `Comment.llm_assists_on(submissions)` (attributed to the submission owner) and `Comment.usage_by_model`; one shared table (`comments/_llm_usage_by_model`) on the user stat card, on its per-contest variant (requests inside the window only) and in a new "AI assist" card on the problem stat page, absent when nobody asked. Columns: model, requests (answered), points, cost — "—" when no row of that model carries a dollar figure, "$x (n of m priced)" when only some do — and tokens in / out.
- **Outcome / status:** on the local prod copy every row shows "—" for cost (the Genie relay reports none, and the column is younger than the rows); real figures accumulate from the Gateway answers since 2026-09-05 (262 rows by the 2026-09-10 deploy). Live on production since 2026-09-10 15:51 (chula_cp 2123).

### 2026-09-09 — An admin's request is free for the student
**platform code** · master 2116
- **Problem observed:** since 2026-09-03 only the owner or an admin can press Get (rev 2084), but an admin asking on a student's behalf still charged the owner the site price — the 11 historical staff requests had all done so.
- **Change:** `Llm::CommentAssist.assist_cost_for(requester:, submission:)`: the site price when the requester owns the submission, 0 otherwise. Used where the charge is stored and by the confirm dialog, which now tells an admin the request does not reduce the student's full score. Dollar cost and tokens are recorded as before; the 100-point spend cap ignores a 0 charge by itself.
- **Outcome / status:** decision dae 2026-09-09 ("when admin click on other, zero cost"). Live on production since 2026-09-10 15:51 (chula_cp 2123).

### 2026-09-05 — New prompt and payload live on production (`codey-core` v2.2 = `course-prep` rev 13; chula_cp 2112 deployed to 10.0.5.50)
**deployment: platform code + prompt data** · chula_cp 2112 (master 2089–2111) deployed by dae via the GitLab job; tag #43 set over ssh by Claude; `course-prep` revs 13 (text), 14 (README)
- **Problem observed:** production had run the 2025-07 prompt text and the old payload (statement PDF, managers, source, verdict string) for the feature's whole life; the evaluation (Parts 1–4) showed the answers were long, multi-issue and, on time limits, handed over the algorithm in words.
- **Change:** (1) code: compiler output on compile errors, per-testcase table, previous answer + diff on repeats, picker guards + 100-point spend cap, token/dollar accounting, name-ordered tags, price as a site setting (`system.llm_assist_cost`, created by data migration on deploy — no `db:seed`); (2) prompt: `codey-core` #43 replaced with rev 13 — the rev 4 text (results table instead of percentage mapping, majority-failure rule, describe-the-algorithm loophole closed, textbook names allowed, ~250-word single-issue shape, trace check, no unverified praise, repeat-request rule) plus the compile-error "fix, recompile, resubmit" sentence. `codey-thai` #44 unchanged. Order kept: code first, prompt second (the prompt assumes the new payload). Old text backed up at `~/codey-tag-43-backup-2026-09-05.txt` on the host (rev 3); rollback = paste it back.
- **Outcome / status:** verified on the host after the switch by assembling the payload for an AL problem (core + Thai addendum, 4 user parts incl. the table and a previous answer) and a DS problem (core only, managers + table) — no network call. Expected from the offline test (same model, 100 real stuck moments): one-issue answers ~46% → ~89%, ~150 words instead of ~240, no code, hand-overs ~11% → ~8%, compile-error answers always ending with a next step; the "states the fix" rate is not expected to move. Re-measure after a term with `frame.rb` (read scores) and `frame2.rb`/`frame3.rb` (outcomes), compile errors and repeat requests first. Post-deploy one-offs still open in `doc/backlog.md`: `rake comments:backfill_llm_usage`, the 397 stuck `processing` comments.

### 2026-09-05 — Follow-up on the two prompt edits: keep the compile-error one, drop the TLE stop rule
**study** · `doc/assist-corpus-eval-2026-09-03.md` Part 4 "Follow-up"; `course-prep` revs 11 (v2.1 tested), 12 (arm-d answers + blind set), 13 (v2.2 = rev 4 + one sentence; reader scores)
- **Problem observed:** Part 4 left two weaknesses in rev 4: compile-error answers that ended on a bare question (15 of 20 had a next step), and time-limit answers that named the allowed tool and then laid out the redesign (6–7 of 18).
- **Change:** one new arm on the 38 CE + TLE inputs with both edits (v2.1), graded blind against the rev 4 answers for the same inputs by the same three readers.
- **Outcome / status:** the compile-error sentence works — next step 7 → 20 of 20 on the stricter reading, gained on 13 inputs, lost none, no side effects. The TLE stop rule does not — hand-overs 7 → 9 of 18 (removed 2, introduced 4); reverted. **Deployable text = `course-prep` rev 13 (v2.2)**, both halves of which have been read blind. The TLE hand-over stays an open problem for a shape-level fix (template or second pass), parked. Still **pending dae**: deploy chula_cp (2112, which carries the key migration), then paste rev 13 into tag #43.

### 2026-09-04 — Offline old-vs-new prompt test: rev 4 fixes focus, not the "states the fix" line
**study** · `doc/assist-corpus-eval-2026-09-03.md` Part 4; data + scripts `course-prep/assist/eval-2026-09-03/offline-prompt-test/` (course-prep revs 6–10)
- **Problem observed:** the eight prompt edits from the 2026-09-03 evaluation (`codey-core` v2, course-prep rev 4) had been accepted on reasoning alone; nothing showed what they do to real answers before students see them.
- **Change:** 100 past stuck moments (20 compile errors, 45 repeat requests, at most 3 per problem) answered three times each by gemini-3.1-pro: old prompt + old payload, old prompt + new payload (rev 2089), new prompt + new payload. 300 throwaway answers, no comment rows, no charge. Graded blind by 12 Claude readers on Part 1's rubric; the DGX few-shot judge scored the same 300 for the cheaper-grader question.
- **Outcome / status:** one-issue answers 46 → 89 of 100 (gained on 45 inputs, lost on 2); hand-overs 11 → 8; wrong diagnoses 3 → 1; no code written; median 152 English words vs 238; numbered checklists 48 → 5. "States the fix" flat at 87–90 of 100 in every arm — the Socratic wording does not make the model withhold the fix. TLE hand-overs unchanged (7 → 6 of 18): the model names the allowed tool, then lays out the redesign anyway. Recommendation in the doc: deploy rev 4 after two small edits (Step 1 next-action sentence; a concrete stop rule after naming a tool in the TLE section), re-run the TLE + CE cells to check them. **Pending dae.** Operational: 12 readers ≈ two 5-hour windows, not one — run 6 + 6; the Thai-strip heuristic needed a fix before grading (33 bodies cut short, re-blinded, 3 re-graded).

### 2026-09-03 — Blind human read of 30 answers (the calibration anchor)
**study** · `course-prep` rev 5 (`assist/eval-2026-09-03/dae-reads.html`, `make_reads_page.py`, `dae-reads-key.json`); rev 2102–2103 (plan + this entry)
- **Problem observed:** every grade in the study so far was given by a model — the 291 read by Claude, then the DGX judges — and the two disagreed most on the line that the main finding rests on: did the tutor merely ask a leading question, or state the fix? No human had ruled on that line.
- **Change:** a single-page form with 30 answers from the 291, chosen where the graders disagreed — 12 where the Claude readers said "Socratic" and the few-shot DGX judge said "stated the fix", 12 the other way round, 6 the readers called algorithm hand-overs — shuffled, student code folded under a click, no grader's score visible. Three questions per answer in plain words (how much was given away / diagnosis right / one issue) plus a note; answers autosave in the browser and export as `dae-reads.csv` into the same directory. The selection key with the graders' scores is kept in a separate file. dae started reading 2026-09-03 evening.
- **Outcome / status:** pending `dae-reads.csv`. Next session joins it to the graders' scores on `comment_id` and reports, per disputed answer, which grader dae sided with — that decides how to read every leak figure in the study and how to calibrate the judge for the offline old-vs-new prompt test.

### 2026-09-03 — The price becomes a site setting
**platform code** · rev 2100; `Llm::CommentAssist.assist_cost`, `db/seeds.rb`, `submissions/_add_assist`
- **Problem observed:** the 10-point penalty was `ASSIST_COST = 10` in the service class — changing it meant a deploy, and there was no agreed place to keep the number. Decided with dae 2026-09-03: keep 10 for now (including for answers that name an algorithm, see the naming decision), but make it adjustable.
- **Change:** `GraderConfiguration['system.llm_assist_cost']` (integer, seeded 10, editable on the Configuration page, audit-logged like every setting); read at request time and stored on the comment; the confirm dialog and the picker quote it; 0 is a valid "free" price. Per-problem or per-contest prices were considered and left for a real need.
- **Outcome / status:** master 2100. Key created on every deployed host by data migration `20260905090000_seed_llm_assist_cost_configuration` (master 2111, 2026-09-05) — runs inside the deploy job's `db:migrate`, idempotent, so no manual `db:seed` is needed anywhere; until a host is deployed the code uses 10.

### 2026-09-03 — Naming decision: the tutor may name textbook algorithms; the problem-specific insight stays off limits
**policy (prompt), pending the prompt edit** · discussion 2026-09-03; evaluation Part 1 finding 1
- **Problem observed:** the "never name an algorithm or data structure" rule was obeyed to the letter and defeated in spirit — 9% of current answers narrate the algorithm step by step unnamed, a fuller leak than the word would be and harder for the student to look up; four property-descriptions of `set::lower_bound` failed to land where the name would have.
- **Change (agreed with dae):** allow naming standard textbook algorithms and data structures taught in the course; forbid the problem-specific step — the recurrence, the invariant, the reformulation, a worked example on the student's problem, solution code; when the fix is a redesign, tell the student to keep the current solution for the subtasks it passes and add the faster path for the rest. Price stays 10 points for now.
- **Outcome / status:** written into `codey-core` rev 4 (TLE section + anti-cheating rule), tested offline 2026-09-04, live on prod 2026-09-05 as part of rev 13.

### 2026-09-03 — Prompt tags: two full copies → `codey-core` + `codey-thai`; name-ordered assembly
**data + platform code** · prod tags #43/#44 (AI-AL #33, AI-DS #34 deleted; backup `~/codey-tag-backup-2026-09-03.txt` on 10.0.5.50); `course-prep` rev 3 (`assist/`); rev 2093
- **Problem observed:** `AI-AL` (239 problems) and `AI-DS` (45) were the same 9.4 KB text except AL's Thai appendix; every edit had to be made twice and they had drifted by one wording change. The tag lookup had no ORDER BY, so multi-tag assembly order depended on attach order.
- **Change:** dry-run then apply of a re-tag script on prod: `codey-core` (AL text minus the appendix) on all 284, `codey-thai` (one sentence) on the 239 AL problems. `CommentAssist` orders tags by name. Prompt text checked into `course-prep/assist/`.
- **Outcome / status:** live on prod (per-problem behaviour unchanged; verified by assembling the payload for an AL and a DS problem). Code in master 2093, on prod with chula_cp 2112 (2026-09-05).

### 2026-09-03 — First corpus evaluation (Part 1 read scores, Part 2 whole-corpus outcomes, Part 3 DGX judge calibration)
**study** · `doc/assist-corpus-eval-2026-09-03.md` (revs 2094, 2096, 2097, 2098); raw frame + scores + `frame2.rb`/`frame3.rb` + `judge.py`/`agreement.py`/`judge-*.csv` in `course-prep/assist/eval-2026-09-03/` (local-only repo; `~/cafe-grader/assist-eval-2026-09-03` is a symlink to it)
- **Problem observed:** no one had read what the tutor actually says. The effectiveness metric showed no visible benefit but could not say why.
- **Change:** frame over all 4,787 answers (verdict class, next-submission outcome, request index, mechanical checks); 291 read against source + evaluations (all 193 current-model answers + 7 per verdict-class × outcome cell of the retired models) and scored on leak / diagnosis / focus / actionable.
- **Outcome / status:** Part 3 (evening): the self-hosted models were calibrated as judges against the 291 read answers — gemma-4-31b matches on focus (κ 0.77) and language only; qwen3.5 reaches κ ≈ 0.5 on leak and wrong-diagnosis but is systematically lenient (calls 38% leaks vs the readers' 60%), so a free census would understate the study's main finding; a few-shot retry with six gold anchors fixed hand-over detection (leak-2 κ 0.65) and focus (0.71) but flipped rather than removed the leak bias (three-way κ 0.49) and hurt diagnosis (0.23) — DGX route for leak/diagnosis stopped; paid targeted sample vs stop-at-291 pending. Part 2 (evening, database only): paired same-student-same-problem improvement 27% → 38%; compile-error and repeat requests are the worst cells; Aug 2026 same-problem head-to-head favours the current models (next↑ 50% vs 38%); two problems absorbed 277 requests with ~2% success. Part 1: hard rules hold; the soft rule fails (64% state the fix, 9% hand over the algorithm in words, mostly TLE/RE, and those students regress as often as they improve); wrong diagnoses are model-specific (gemini-3.1-pro 0/90, Claude-Sonnet 8/40); the current models are twice as long and half as focused as gemini-2.5-pro was. Eight prompt edits and two roster/Thai decisions listed in the doc — **pending dae**.

### 2026-09-03 — Picker guards: in-flight, already answered, full score, 100-point spend cap
**platform code** · rev 2090; `Submission#llm_assist_refusal`, `submissions/_add_assist`, `CommentsController#can_request_llm`
- **Problem observed:** 190 submissions had the same model asked twice, 126 requests were made on full-score submissions, 10 student–problem pairs had spent more than the problem was worth — each a wasted API call and, until rev 2085, a negative score.
- **Change:** one predicate disables Get with the reason shown, and the controller applies it to a replayed form (422). The picker refreshes with the comments so a finished request re-enables Get.
- **Outcome / status:** master 2090, on prod 2026-09-05 (chula_cp 2112). Side effect: the 397 historical stuck-processing comments now also block new requests on those submissions until cleared (one-off recorded in `doc/backlog.md`).

### 2026-09-03 — Payload rebuilt around what the grader knows; dollar/token accounting
**platform code** · rev 2089; `Llm::CommentAssist`, migration `AddLlmUsageToComments`, `rake comments:backfill_llm_usage`
- **Problem observed:** the model was asked to infer subtask boundaries from percentages in the PDF and to find syntax errors without the compiler message (166 assisted compile errors); repeat requests (44%) arrived with no memory of the previous answer, so students got the same hint again; no record of what a request cost in dollars or tokens.
- **Change:** compiler output block on compile errors; per-testcase table from `evaluations` (group, verdict, time, memory, score, dataset limits, ≤100 rows, never inputs or answers); previous answer + line diff (or "code unchanged") with an instruction not to repeat; `llm_cost` / `prompt_tokens` / `completion_tokens` columns filled from the response (gateway cost header; self-host 0.0; nil where no source), backfill recovers tokens for 5,098 historical rows.
- **Outcome / status:** master 2089, tests cover each block; on prod 2026-09-05 (chula_cp 2112) together with the rev 13 prompt that reads the new parts.

### 2026-09-03 — Seven defects fixed
**platform code + security** · revs 2084–2086, merged to chula_cp 2088 and pushed
- **Problem observed:** (1) any logged-in user could request assist on any submission id, charging its owner and the API budget, on a submission they could not view; (2) the model was addressed by its index in the provider map (an `llm.yml` reorder repointed every link; a stale index was a 500); (3) `final_score` could go negative; (4) the model-written answer was rendered as raw HTML (stored-XSS class); (5) a problem without a statement PDF produced a `null` content part (400); (6) a failed request got two error blocks; (7) the picker was a `link_to` with `turbo_method`, against the mutating-click convention.
- **Change:** owner-or-admin gate; model by name via a `button_to` form; `GREATEST(0, …)`; sanitize after markdown; `.compact`; job leaves a comment the service already marked; regression tests for each.
- **Outcome / status:** live in the repo (chula_cp 2088); deployed to 10.0.5.50 on 2026-09-05 (chula_cp 2112).

### 2026-08-26 → 08-30 — Chula AI Gateway provider; claude-opus-4-5 and gemini-3.7-flash join the picker
**platform code + config** · revs 2018–2019, 2050; chula_cp `llm.yml`
- **Problem observed:** the only hosted provider was ChulaGenie, whose relay could not take PDFs for Anthropic models and reported no cost.
- **Change:** generic bearer-key OpenAI-compatible transport (LiteLLM proxy / OpenRouter shape) with one subclass per role; PDF parts rewritten to `file` blocks; per-call cost from the gateway header (with a body fallback and a WARN when neither is present). chula_cp registers `AiGatewayAssist: claude-opus-4-5,gemini-3.7-flash`.
- **Outcome / status:** first prod answers 08-27 (opus) and 08-28 (3.7-flash); no errors since.

### 2026-08-23 — Comment assist defaults to gemini-3.1-pro; Claude-Sonnet un-broken
**config + platform code** · revs 2006–2007 (chula_cp)
- **Problem observed:** the Genie relay had renamed its Claude models in February; `llm.yml` followed (rev 1498, 02-14) but `GenieAssist::PERMITTED_MODEL` still listed `Claude-3.5-Sonnet`, so every "Claude-Sonnet" request since 02-14 was silently downgraded to gemini-2.5-pro. gemini-2.5-pro itself was due to retire.
- **Change:** allowlist uses the relay's current names; default model gemini-3.1-pro (smoke-tested with a statement PDF); rosters refreshed.
- **Outcome / status:** gemini-3.1-pro first answer 08-24; Claude-Sonnet genuinely served from 08-24 (40 answers to 09-02). gemini-2.5-pro's last answer 08-23.

### 2026-07-30 — Self-hosted provider (`SelfHostAssist`)
**platform code** · revs 1932–1933; chula_cp `llm.yml` `self_hosted_models`
- **Problem observed:** the near-miss grading work needed the department's DGX models; the same transport can serve the assist picker at zero dollar cost.
- **Change:** `SelfHostChat` transport + `SelfHostAssist`; served model names registered in the provider map appear in the picker.
- **Outcome / status:** built and tested; not registered in the prod picker as of 2026-09-03 (no DGX model has answered a student request).

### 2026-07-20 → 07-21 — `llm_prompt` means the helper prompt only (viva tag taxonomy, D6)
**platform code + data** · revs 1878, 1888–1889, 1892; `doc/decisions.md` 2026-07-20
- **Problem observed:** viva and the helper both read `kind: llm_prompt`, so a bulk-tagged tutor persona could concatenate into an examiner's system prompt and vice versa. The spec's first cut hid `llm_prompt` from the generic tag picker, which silently detached helper tags on every ordinary problem save.
- **Change:** viva moves to `problems.viva_prompt` + `viva_conduct` tags; `llm_prompt` is read only by `CommentAssist`; the generic picker keeps offering it. Both LLM kinds forced `public = false`.
- **Outcome / status:** live since 4.4.x/4.5.0. One leftover: `AI_viva` (#36) is still an `llm_prompt` tag on two viva problems and is read by nothing.

### 2026-05-07 — `Llm::Request` hierarchy; `CommentAssist` lifted out of `GenieAssist`; penalty regression and fix
**platform code** · revs 1634–1654 (master + chula_cp merges)
- **Problem observed:** the comment-assist logic lived inside the Chula-specific `GenieAssist`, so master had no working helper and every provider would have re-implemented message assembly.
- **Change:** abstract `Llm::Request` (orchestration, retry taxonomy, Faraday factory) → `CommentAssist` (payload + comment handling) → provider subclasses. `Request.preview` for console inspection of the payload. The lift briefly replaced the 10-point penalty with a 0.0 "API cost"; rev 1642 restored it as `ASSIST_COST = 10` with the semantics documented.
- **Outcome / status:** every later provider (self-host, gateway) plugged into this shape unchanged.

### 2026-03-04 — More error handling on Genie assist
**platform code** · rev 1509 (chula_cp)
- **Problem observed:** Feb–Mar 2026: 74 Claude-3.5-Sonnet requests failed with HTTP 400 (Anthropic rejects a PDF sent as an `image_url` part) and surfaced as bare "API Communication Error".
- **Change:** clearer error handling on the Genie call path.
- **Outcome / status:** the underlying PDF shape problem was only solved by the gateway transport (08-26); Claude-3.5-Sonnet's last answer was 03-03 and the renamed model was silently downgraded until 08-23 (see that entry). The Thai-translation appendix on `AI-AL` dates from this period at the latest (tag `updated_at` 03-04).

### 2025-11-25 — Score summation of assists fixed
**platform code** · revs 1482, 1486
- **Problem observed:** the max-score report summed the penalty incorrectly across a student's submissions.
- **Change:** `max_score_report` joins the assist penalty per submission and applies `min(max, 100 − llm − hint)`.
- **Outcome / status:** stayed until the 2026-09-03 floor fix (rev 2085).

### 2025-09-14 — Contest views show hint and assist penalties
**platform code** · revs 1429–1430
- **Change:** the contest score table shows the assist count/cost and hint cost next to the raw and final scores.
- **Outcome / status:** live; the same numbers drive the Best Score report.

### 2025-08-23 → 08-26 — Managers in the payload; missing-tag error; auto refresh
**platform code** · revs 1397, 1401, 1406
- **Problem observed:** problems with manager files (headers, main programs) gave the model no context on how the student's code is called; a problem without an `llm_prompt` tag failed opaquely; students had to reload to see the answer.
- **Change:** managers sent as JSON with a do-not-reveal instruction; explicit "no `llm_prompt` tag" toast; the comments block polls every 5 s while a request is processing.
- **Outcome / status:** live. The polling is what made the 397 stuck-processing comments visible as eternal spinners.

### 2025-07-23 — First student request
**operations** · production
- gemini-2.5-pro and Claude-3.5-Sonnet in the picker from day one. 725 requests in August 2025.

### 2025-06-29 → 07-17 — Birth
**platform code + schema** · revs 1299–1347; migrations `add_llm_support_to_comment` (06-29), `add_llm_enable_to_contest_problem` (07-11), `add_json_params_to_tags` (07-15)
- **Change:** `comments.llm_response / llm_model / status` and `kind: llm_assist`; `GenieAssist` against ChulaGenie; the "acquire" confirm dialog stating the 10-point price and what is sent; per-model provider map in `llm.yml` (`GenieAssist: gemini-2.5-pro,Claude-3.5-Sonnet`); `system.llm_assist` site switch; `contests_problems.allow_llm`; tags gain `params` and the `llm_prompt` kind, and the prompt moves from code into a tag attached per problem.
- **Outcome / status:** the shape that still stands: prompt in tags, price in score, provider by config.
