# Near-Miss Grading

**Near-Miss Grading** is a batch research instrument that measures how close each failing submission is to a working one. For every below-full-score submission in a contest, an LLM proposes the smallest fix it can within an explicit modification budget (default **2 lines / 20 characters**), a deterministic gate rejects any over-budget patch, and accepted patches are graded by the **real judge pipeline** as linked, student-invisible **shadow submissions**. The headline number per attempt is the **mechanical gap** — `repaired_score − original_score`.

**v1 is an instrument, not a student feature.** It runs from the command line (`rake near_miss:repair` / `near_miss:report`), records every attempt (including failures — "the LLM could not fix it within budget" is a data point, not an error) in `submission_repairs` rows, and surfaces the results in a read-only admin browser (**Report → Near-Miss Runs**). Nothing a student can see changes: shadow submissions are excluded from every student-visible query and quota count, and no real score is ever modified.

**Related docs:**
- `docs/superpowers/specs/2026-07-30-near-miss-grading-design.md` — the approved design (D1–D8), data model, gate algorithm, self-hosted transport. This document supersedes its open questions where the two disagree; the spec remains authoritative for implementation detail.
- `docs/superpowers/plans/2026-07-30-near-miss-grading.md` — the 10-task implementation plan (revs 1928–1939 on master).
- `doc/backlog.md` (Near-Miss sections) — the genuinely-open follow-ups: the hardening batch, the student-facing phase, and the `problems.statement_text` design.
- `doc/decisions.md` (2026-07-30 entry) — LLM-provider branch placement: generality decides the branch, so the generic self-host classes live on `master` while the ChulaGenie-only repair provider lives on `chula_cp`.
- `config/llm.yml` on master — commented, copy-ready config examples for the self-hosted providers.

---

# What It Measures and Why

The grader is rigidly summative: a submission that fails input parsing, output format, or compilation scores 0, indistinguishable from a submission with no algorithmic understanding at all. The instrument has a **floor effect** — it measures nothing below "compiles and parses I/O correctly", which is exactly where below-average students live. A student whose correct algorithm dies on a missing `#include` and a student who never got past reading the problem both read as zero.

Near-Miss Grading removes that floor with **bounded-repair evaluation**. A small modification budget naturally captures mechanical failure classes (I/O format, parsing, syntax, off-by-one) and excludes algorithmic rewrites — which is precisely the pedagogical line: forgive mechanical errors, not conceptual ones. If a two-line, twenty-character patch takes a submission from 0 to 100, the zero was measuring a typo, not understanding.

The batch data exists to answer, with evidence rather than intuition, what the eventual student-facing pedagogy should be (lifeline economy, staged hints, real-time repair — deliberately undesigned in v1, decision D7). The a68_final run was the first contest-scale measurement; see "Experimental Record" below.

---

# How a Repair Attempt Works

One attempt = one `SubmissionRepair` row, created `pending` and driven through:

1. **LLM call** (`Llm::SubmissionRepairJob` → the configured `Llm::SubmissionRepairAssist` subclass). The prompt contains the original source (wrapped in prompt-injection defense framing — student source is untrusted input), a human-readable verdict (per-testcase results decoded from `grader_comment`, compiler output for compile errors), the budget stated explicitly, and the output contract: return the **complete corrected file** in a fenced block plus one fix-category token and a one-sentence reason. The statement is deliberately **not** included (see "Settled Design Decisions").
2. **Gate** (`SubmissionRepair::Gate`, pure and LLM-free): normalize both sources (CRLF→LF, strip trailing whitespace, single trailing newline — nothing else), diff with `diff-lcs`, measure `changed_lines` (paired delete+add = 1 modified line; hunk contribution = `max(deletions, additions)`) and `changed_chars` (Levenshtein per paired line, full length for unpaired lines). Accept iff **both** measures are within budget.
3. **Retry loop**: a gate rejection (or unparseable output) consumes a round and the retry prompt states the measured size vs the budget ("your patch changed 34 chars; the budget is 20"), up to `ROUNDS` total LLM calls (default 3). Every round's measurement lands in `rounds_log` — that's what powers the per-model per-round budget-compliance analysis.
4. **Shadow submission** on acceptance: same user/problem/language, source = patched file, `repaired_from_id` = the original, created in the **same transaction** as the row update so linkage cannot drift. Graded via the standard judge path at priority −60 — below interactive rejudge (−10) and dataset rejudge (−50), so a batch never starves interactive work.

Attempt statuses:

| Status | Meaning |
|---|---|
| `pending` / `processing` | queued / in flight |
| `accepted` | gate passed; shadow submission created and sent to the judge |
| `over_budget` | LLM produced parseable code every round, but always over budget |
| `no_change` | normalized sources identical, or the LLM declared it unfixable within budget |
| `failed` | LLM/transport failure after job retries, or no parseable file in any round |

Fix categories (LLM self-report, validated against the enum, invalid ⇒ `other`): `io_format`, `parsing`, `syntax`, `boundary`, `logic`, `other`.

## Shadow submissions are invisible to students

`submissions.repaired_from_id` marks a shadow; **`Submission.regular`** (`repaired_from_id: nil`) is the scope every student-visible query and quota count reads — main-list scores, submission counts, contest scoreboards, plagiarism comparison, viva daily-start counting, per-problem stats. Students cannot see shadows even for their own submissions (`can_view_submission?` denies them); admins and reporters can. Shadows are never targets for a later repair run (`batch_targets` reads `Submission.regular` too).

---

# Operator Guide

## Prerequisites

- **`config/llm.yml`** must name a repair provider. Blank on master (the abstract base then raises `NotImplementedError` — intentional "no provider configured" signal, same convention as the viva service keys). On a deployment branch:

  ```yaml
  submission_repair_service: Llm::SubmissionRepairSelfHostAssist
  self_hosted_default: qwen
  self_hosted_models:
    qwen: { base_url: "http://<dgx>:8000", completion_path: "/v1/chat/completions", model: "qwen3.5", max_tokens: 16384 }
  ```

  A commented, copy-ready block lives in master's `config/llm.yml`. **`max_tokens: 16384` is required for the DGX reasoning models** — at 4096 they spend the whole completion budget thinking and return empty content (`finish_reason: length`; pilot-verified). Keys of `self_hosted_models` are operator labels — model identity is config data, never code. On `chula_cp`, `Llm::SubmissionRepairGenieAssist` (ChulaGenie) exists as an alternative provider.
- **A Solid Queue worker must be running** (`bin/rails solid_queue:start`) — repair attempts are ordinary jobs.
- **The judge must be able to grade the target problems** — see "Missing Active Storage blobs" below before running on a dev copy.

## Running a batch: `rake near_miss:repair`

```
rake near_miss:repair CONTEST=<id> [PROBLEM=<id>] [SUBMISSION=<id>]
     [SCOPE=latest|all] [MIN_SCORE=<n>] [MAX_SCORE=<n>]
     [BUDGET_LINES=2] [BUDGET_CHARS=20] [ROUNDS=3]
     [SERVICE=<self-host key>] [RUN=<label>] [LIMIT=<n>] [DRY=1]
```

| Parameter | Meaning |
|---|---|
| `CONTEST` (or `SUBMISSION`) | required — the contest whose submissions are targeted, or a single submission id for a one-off. `PROBLEM` narrows to one problem. |
| `SCOPE` | `latest` (default): the latest submission per (user, problem), kept only if below full marks. `all`: every below-full submission — beware, this multiplies *judge* load, not LLM load. |
| `MIN_SCORE` / `MAX_SCORE` | bound the original score for stratified runs (e.g. a zeros-only run vs a 1–99 run under different labels). |
| `BUDGET_LINES` / `BUDGET_CHARS` | the gate budget (defaults 2 / 20). |
| `ROUNDS` | total LLM calls per attempt (default 3). |
| `SERVICE` | which `self_hosted_models` key to use (default: `self_hosted_default`). When `submission_repair_service` points at a non-self-host provider (e.g. Genie on chula_cp), the value is passed through as that provider's model name. |
| `RUN` | the run label (default `contest<id>-<date>`). Run identity everywhere — report, browser, resume. |
| `LIMIT` | cap the target count, for pilots. |
| `DRY=1` | print target count + per-problem breakdown and exit; nothing enqueued. |

Operational notes:

- **Target selection** takes regular (non-shadow), non-viva submissions in status `done` or `compilation_error`, below full marks (`points < 100`) on a problem whose live dataset has a normalized score type. **`raw_sum` problems are skipped** (no defined full score) and listed in a NOTE at launch. Single-`SUBMISSION` mode bypasses the viva exclusion — don't point it at a viva submission.
- **Model-identity guard:** for self-host runs, the task calls `GET <base_url>/v1/models` once at startup and **aborts on mismatch** between the served model and the configured one. This exists because the DGX echoes whatever `model` string you send without validating it, and its ports are swap slots — a redeployed port could silently answer as a different model, which would be fatal for run comparability. A swapped-out port refuses TCP, which fails fast with a clear message.
- **Resume semantics: run labels key on row existence, not status.** Re-running the same `RUN=` label skips every submission that already has an attempt row, so a crashed batch resumes by re-running the same command. The flip side: a batch that failed *wholesale* (bad config, dead endpoint) has consumed its label — after fixing the config, **pick a fresh label**; the old rows won't be retried.
- **Watch progress** with the snippet the task prints: `SubmissionRepair.where(run_label: '<label>').group(:status).count`. Solid Queue's concurrency naturally throttles the LLM endpoint.
- Expect roughly **30–60s per attempt on qwen** (reasoning models think); the 201-target a68_final run took 131 minutes end to end.

## Reading results: `rake near_miss:report`

```
rake near_miss:report RUN=<label>[,<label>...]      # or CONTEST=<id>
```

`CONTEST=<id>` picks up every label matching `contest<id>-…`. Output is a per-run, per-problem console table plus a CSV (path printed, under `tmp/`): targets, status counts, **rescued** (accepted attempts whose shadow outscored the original) and rescue rate, mean/median mechanical gap, fix-category histogram, median measured patch size (how much of the budget real fixes actually used), per-round budget compliance (how often each model's patch was within budget on round 1, 2, 3 — from `rounds_log`), and tokens/cost.

**Ungradeable shadows are excluded from gap stats** (fixed 2026-08-02, after the void a68_final grading pass — see the experimental record): an accepted attempt whose shadow has no real judge outcome (`grader_error`, or still in flight) is reported as an explicit `ungradeable` count — in the rake table, the CSV, and the run browser — and never enters the gap/rescue statistics as a fake 0-point grade. A shadow in `compilation_error` *is* a real outcome (the repair broke the build — damage data) and stays in the stats. A large `ungradeable` count means judging infrastructure trouble (usually missing blobs on a dev copy), not model behavior.

## The web browser: Report → Near-Miss Runs

Admin-only, read-only (`/near_miss/runs`); the data is produced solely by the rake tasks. Three levels:

- **Runs index** — every run label with attempt/problem counts, status rollup, rescued count, models, budgets, token/cost totals; checkboxes to select several runs and compare.
- **Run report** (`/near_miss/run?runs=a,b`) — the same per-problem tables as `near_miss:report`, rendered side by side per run (the comparison view for budget experiments and model shootouts), plus the attempt list filterable by status. `?runs=` accepts the same comma syntax as the rake `RUN=` parameter, so report URLs are shareable.
- **Attempt detail** (`/near_miss/repairs/:id`) — the gate-computed patch (colored diff), per-round log with measured sizes and gate outcomes, category/remark, tokens/cost, raw LLM response, and links to the original and shadow submissions.

## Missing Active Storage blobs on a dev copy: `sync:problem`

A dev database migrated from production usually has **partial Active Storage files** — the DB rows exist but `storage/` lacks the blobs. Two distinct failure signatures in near-miss runs:

- **Missing testcase input/answer blobs** → the judge 404s when downloading them → **every accepted shadow lands in `grader_error`**. Combined with the report bug above, this masquerades as catastrophic model damage ("0 rescues, 63 negative gaps"). It is not: verify by re-grading an identical copy of a known-good submission — if that also `grader_error`s, it's the blobs.
- **Missing statement blob** → only affects providers that attach the statement PDF (`encode_pdf_part` raises on a registered-but-missing blob and the attempt row lands in `failed`). The default self-host repair prompt is text-only and never hits this.

The remedy is `rails "sync:problem[<id>]"` — rsyncs one problem's complete Active Storage set (statement, attachment, checker, managers, testcase in/ans files) from a remote host into local `storage/`. Override the source with `REMOTE_HOST=` (bare host or `user@host`) and `REMOTE_RAILS_ROOT=`; run without an id for help. After syncing, shadows are re-gradeable in place (`add_judge_job` on each shadow — attempt rows are untouched, no fresh label needed, since the LLM phase was valid).

---

# Settled Design Decisions

The spec's D1–D8 record the pre-implementation decisions; the ones below are the ones that matter operationally, updated with what the experiments settled.

## The gate is deterministic and size-only — the judge is the correctness oracle

The score is never an LLM opinion. The gate measures patch magnitude (lines + chars, computed from a normalize-then-diff that a human can re-derive) and nothing else — no AST analysis, no comment stripping, no judgment of whether the fix is "reasonable". That keeps it auditable, explainable, and immune to prompt injection via student source. The consequence is deliberate: **a within-budget patch that breaks working code passes the gate** — and the real judge then grades it down. Damaged repairs are data (they measure model safety), not a gate failure; the gate's job is only to hold the mechanical/conceptual line by size. Corollaries: the LLM returns the complete corrected file, never a diff (models mangle diff syntax; we diff deterministically anyway), and shadow grading runs through the unmodified judge pipeline so repaired scores are exactly comparable to real ones.

## Scoring policy: `max(original, repaired)` — never replacement

If repaired scores ever touch anything student-facing, the only defensible combiner is `max(original, repaired)`. This was a hypothesis after the Genie batch (3 of 18 accepted repairs *broke working 60–70-point code into compile errors*) and became mandatory at contest scale: in a68_final, **18% of accepted repairs scored below the original**. Bounded repair can subtract as easily as it adds; a max() policy makes damage invisible to the student while preserving every rescue. Report analysis should always separate positive, zero, and negative gaps for the same reason.

## qwen (self-hosted) is the default provider

Decision D6 (marginal cost ≈ 0 *is* the cost strategy), confirmed empirically by the model comparison: **paid models do not rescue better**. On the same 10 submissions, qwen rescued 2 for $0, gemini-3.1-pro rescued 2 for $1.14, Claude-Sonnet rescued 0 for $0.16 (fast, but it wants 3–31-line rewrites — chronically over budget). The paid models' genuine edge is *safety* (gemini-3.1-pro: zero negative gaps), which matters for a student-facing phase but not for a free batch instrument whose damage is filtered by max(). Genie cost ≈ $0.87 per rescue in the 23-submission batch; qwen's is zero. `SERVICE=`/`submission_repair_service` keep every alternative one config edit away.

## Statements are OFF for repair prompts

Two independent reasons. Mechanically: sglang rejects PDF content parts in both wire shapes, so the self-host provider is text-only by construction (`include_statement_pdf?` hook). Empirically — and this is the reason it *stays* off even where PDFs would work: the three-arm statement experiment (none / extracted text / rendered PNG, same 10 submissions, qwen) showed **statement richness raises the model's confidence faster than its correctness**. The text arm accepted the most patches (7/10) but produced the most damage (2 negative gaps, 2 compile-broken) and *fewer* rescues (1) than the statement-less baseline (2); the PNG arm was safest but ~5× slower. The verdict beat: for *repair*, the failing code plus the judge verdict is signal enough; the statement mostly emboldens rewrites. (The submission-*assist* path is a different story — see `problems.statement_text` in `doc/backlog.md`.)

## Budget and rounds semantics

The default budget (2 lines / 20 chars) is the mechanical/conceptual proxy line, stated to the LLM and enforced by the gate. `ROUNDS` (default 3 total calls) exists because self-hosted calls are free and a stingy cap under-reports the rescue rate — it records "unfixable" when the model was merely sloppy; every retry is fed the measured size vs the budget. Round-1 budget compliance is a *model property worth tracking* (qwen ~77–100%, gemini-2.5-pro ~57%, Claude-Sonnet near zero), which is why `rounds_log` captures every round even for eventually-accepted attempts. The cap is also the cost ceiling for paid providers — gemini thinks 10–20k tokens per call, so a 3-round budget-fight costs real money ($0.60 observed for one truncation-retry spiral).

## Other settled points, one line each

- **`max_tokens: 16384`** for DGX reasoning models — 4096 yields empty content (all thinking); the pilot's fix succeeded in one 8.6s round at 16384.
- **Viva submissions are excluded** (D8) — the size budget is only a valid mechanical/conceptual proxy for *code*; in natural language a tiny edit ("O(n)" → "O(lg n)") is a conceptual change.
- **Run labels are the unit of comparison** — budget experiments, model shootouts, and score-band studies are all "same targets, different label", rendered side by side by the report and browser.
- **Student-facing phase deferred until the data is digested** (D7) — the batch instrument must not silently pre-decide the pedagogy; the a68_final data now exists for that decision.
- **The repair system prompt stays in code** (decided 2026-08-02) — the prompt is part of the experimental setup: pinned by rev, every run label stays reproducible. A `GraderConfiguration`-editable prompt would silently break run comparability unless the prompt (or its hash) were recorded per attempt — a bigger design than a config key. Revisit only if between-batch prompt iteration on production becomes a real workflow.
- **Both self-host boxes share one multimodal contract** (probe-verified: qwen3.5 on the DGX/sglang 2026-07-31, gemma-4-31b on the A100/vLLM 2026-08-02): object-form `image_url` PNG is accepted and understood; the bare-string Genie shape and PDF media are rejected with 400s. The A100 box also validates model names per request (404 on a wrong name), confirming the identity-guard design assumption. Kept on record because it makes rendered-PNG statements a real option for the *assist* path; if ever adopted, render once per problem keyed on the statement blob checksum and keep statement parts first in the message so the prefix cache reuses them across submissions.

---

# Experimental Record

Five studies, 2026-07-30 → 2026-07-31. All budgets 2 lines / 20 chars, 3 rounds, unless noted.

## 1. First pilot — one submission, end to end (2026-07-30)

Dev copy, live qwen3.5. Submission 919133 (C++, `compilation_error`, 0 points): qwen proposed `+#include <cstdint>` — 1 line / 18 chars, category `syntax` — the gate accepted, and the real judge graded the shadow **0 → 100 (all 20 testcases P)**. Proved the full loop: target selection → LLM → gate → shadow → judge → report/CSV.

Fixes it forced (all landed): text-only self-host prompts (sglang rejects PDF parts in both wire shapes), `max_tokens` 4096 → 16384 for reasoning models (4096 = all-thinking, empty content, 3 unparseable rounds), `gem "csv"` on Ruby 3.4.

## 2. ChulaGenie batch — `genie-pilot-1` (2026-07-31)

23 targets across 2 practice problems, gemini-2.5-pro, **$6.08**, ~74 min. Results: 18 accepted / 3 over_budget / 2 failed (>300s timeouts). Of the 18 judged: **7 rescued (3× full 0→100), 8 zero-gap, 3 negative** — the negatives were working 70/60/70-point submissions broken into compile errors. First evidence for the max() policy. Practice-problem rescue rate ~30% (7/23); ≈$0.87 per rescue. Round-1 budget compliance ~57% (vs qwen's 100% on its 1-sample pilot); gemini spends 10–20k thinking-tokens per call.

## 3. Statement-format experiment — `qwen-stmt-none/text/png` (2026-07-31)

Three arms on the **same 10 submissions**, qwen, varying only statement presentation: none / pdf-reader extracted text / rendered PNG pages.

| Arm | Accepted | Rescues | Negative gaps | Median latency |
|---|---|---|---|---|
| none (baseline) | — | **2** | 1 | 28s |
| extracted text | 7/10 (most) | 1 | 2 (+2 compile-broken) | 19s |
| rendered PNG | 2/10 | 1 | 0 | 98s |

Verdict: statement richness raised *acceptance*, not *correctness* — more confidence, more damage, no more rescues. Repair stays statement-less. Side findings: `pdf-reader` drops Thai combining marks (สระบน/ล่าง + วรรณยุกต์) from our statement PDFs — readable but degraded, the origin of the `problems.statement_text` editable-draft design; PNG vision calls are ~5× slower (vision prefill + longer thinking).

## 4. Model comparison — qwen vs gemini-3.1-pro vs Claude-Sonnet (2026-07-31)

Same 10 submissions again, statement-less, via the upgraded Genie provider (per-model rates, live model allowlist).

| Model | Accepted | Rescues | Negative gaps | Median latency | Cost |
|---|---|---|---|---|---|
| qwen3.5 (self-host) | 4 | 2 | 1 | 28s | $0 |
| gemini-3.1-pro | 6 | 2 (a +100 incl. a 0-char blank-line fix, and a +10) | **0** | 54s | $1.14 |
| Claude-Sonnet (relay) | 3 | 0 | 0 | **9.5s** | $0.16 |

Verdict: paid ≠ better rescuer; qwen stays default. gemini-3.1-pro's real differentiator is **safety** (zero damage) — relevant to a future student-facing phase. Claude via the relay is fastest and cheapest but ignores the edit budget (3–31-line rewrites → `over_budget` ×4).

## 5. Contest scale — `a68final-qwen-1` (2026-07-31)

The first full-contest run: **201 targets** (latest below-full submission per student across the a68 final's 4 problems), qwen, $0, 131 minutes. LLM phase: 158 accepted (79%), 27 no_change, 15 over_budget, 1 timeout; round-1 compliance ~77%.

**The first grading pass was void — a lesson in instrument failure.** All 158 shadows landed in `grader_error`: the judge 404'd downloading the a68 testcase input blobs (partial dev Active Storage sync — DB rows without files). Because `report_for` counts error shadows as 0-point grades, the report read "0 rescues, 63 negative gaps", indistinguishable at first glance from catastrophic model damage. Both model damage and dataset drift were ruled out by a control: re-grading *identical copies* of good submissions also `grader_error`'d. Remedy: `sync:problem` for the four problems from production storage, then re-grade the existing shadows in place (attempt rows intact — the LLM phase was never invalid).

**Real results after the re-grade** (158 accepted, judged):

| Outcome | Count |
|---|---|
| Rescued (positive gap) | **17** — 7 of them to full 100; gaps median 25 / mean 36.8 / sum 625 points |
| Zero gap | 112 |
| Negative gap (damage) | 29 — **18% of accepted** ⇒ max() policy mandatory |
| Shadow compile-broken | 37 |

Contest-scale rescue rate: **8.5%** of 201 targets — versus ~30% on practice problems. The population explains the drop: only 4 of the 201 targets were compile errors (197 were `done`) — a final's below-full submissions mostly embody *conceptual* shortfalls, exactly what a bounded budget is designed not to fix. Per-problem rescue rates ranged 0–16% (important_roads 16.1%, cross_province 11.1%, horse_running 5.1%, weight_change 0%), i.e. the instrument also measures how "mechanically brittle" each problem's I/O and edge structure is.

## What the five studies settle, together

1. The pipeline is sound end to end at contest scale, at $0 marginal cost, on department hardware.
2. **Rescue rate is population-dependent**: ~30% on compile-error-rich practice pools, 8.5% on a final. The floor effect is real but a final's floor is mostly conceptual.
3. **Damage is systemic across all models** (18% of accepted at scale) → any student-facing use must score `max(original, repaired)`.
4. Statements don't help repair; free qwen matches paid rescuers; paid buys safety, not capability.
5. The instrument needed one correctness fix before the next big run: excluding ungradeable shadows from gap stats — fixed in the 2026-08-02 hardening batch (`report_for` now reports them as `ungradeable`).

---

# Known Gaps & Open Work

All tracked in `doc/backlog.md` (Near-Miss sections); headline items:

- **Hardening batch — landed 2026-08-02**: the `report_for` ungradeable-shadow exclusion, the 600s self-host read timeout, the fail-fast on `finish_reason: length` truncation (attempt fails with a "raise max_tokens" remark instead of burning retry rounds), and the compile-error verdict cleanup. The repair-prompt-promotion question was closed the same day — the prompt stays in code (see "Settled Design Decisions").
- **`problems.statement_text`** — pdf-reader-extracted, human-editable statement text on Problem (fixes the Thai-combining-marks loss). Consumer is the *assist* path, which is also what unblocks registering `Llm::SelfHostAssist` in the assist model picker (its inherited prompt still sends the statement PDF, which sglang 400s).
- **Student-facing phase** (D7) — interaction model, lifeline economy, GraderConfiguration budget keys; to be designed from the batch data above.
- Minor recorded caveats: single-`SUBMISSION` mode bypasses the viva exclusion; a wholesale-failed batch consumes its run label (resume keys on row existence); reporters (staff) can view shadow submissions — a deliberate deviation from the spec's "admin-only".
