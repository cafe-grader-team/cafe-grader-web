# Near-Miss Grading (v1: batch instrument) + self-hosted LLM providers — Design

- **Date:** 2026-07-30
- **Status:** approved design, pre-implementation
- **Feature name:** Near-Miss Grading (student-facing name deferred; shortlist: "Second Chance", "Lifeline")
- **Internals name:** `SubmissionRepair` (mechanism-named); rake namespace `near_miss:`
- **Key metric:** *mechanical gap* = `repaired_score − original_score`

## 1. Problem & motivation

The grader is rigidly summative: a submission that fails input parsing, output
format, or compilation scores 0, indistinguishable from a submission with no
algorithmic understanding at all. The current instrument has a **floor effect**
— it measures nothing below "compiles and parses I/O correctly", which is
exactly where below-average students live.

Near-Miss Grading removes that floor with **bounded-repair evaluation**: an LLM
proposes the smallest fix it can within an explicit modification budget (e.g.
2 lines / 20 chars), a deterministic gate rejects any over-budget patch, and
the *real judge pipeline* grades the patched code. A small budget naturally
captures mechanical failure classes (I/O format, parsing, syntax, off-by-one)
and excludes algorithmic rewrites — precisely the pedagogical line: forgive
mechanical errors, not conceptual ones.

**v1 is a research instrument, not a student feature.** It runs from the
command line over a contest's submissions and produces data (mechanical-gap
distribution, fix-category histogram, repair-size distribution) so the
student-facing pedagogy (lifeline economy, staged hints, real-time repair) can
be chosen from evidence later. No UI, no score changes, no student visibility.

## 2. Goals (v1)

1. Repair engine: LLM proposes a bounded fix → deterministic LLM-free gate →
   accepted patches graded by the normal judge as linked shadow submissions.
2. Batch CLI: `rake near_miss:repair` over a contest (or narrower target) +
   `rake near_miss:report` producing the analysis tables.
3. **Self-hosted providers (second feature):** a shared OpenAI-compatible
   transport for the department's models — `qwen3.5` (DGX swap slot) and
   `gemma-4-31b` (always-on A100 box) — wired into *both* Near-Miss repair and
   the existing submission assist (`Llm::CommentAssist` family).
4. Full accounting per attempt: tokens, dollar cost, rounds, fix category, raw
   response — viva-style, so `/report/ai`-grade cost visibility exists from
   day one.

## 3. Non-goals (v1)

- No student-facing UI, lifeline economy, or real-time repair flow.
- No effect on real scores — shadow submissions are excluded from every
  student-visible query and quota count; scoring policy (penalties, caps) is
  deliberately undesigned until the batch data exists.
- No new `GraderConfiguration` keys — budgets are rake parameters. Admin-editable
  defaults arrive with the student-facing phase.
- No web report page; console/CSV output only.
- No AST-based or comment-stripping diff metrics (keep the gate explainable).

## 4. Decisions already made (brainstorm outcomes)

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Fixed budget, stated to the LLM, **enforced by a deterministic gate** computable without any LLM | Owner decision. The score is never an LLM opinion; the gate is auditable and immune to prompt injection via source code |
| D2 | Evaluation channel = **shadow submissions** through the normal judge pipeline, with explicit linkage to the original | Real scores with identical semantics (sandbox, dataset, partial credit); zero judge-worker changes. Alternatives rejected: separate channel (requires external-worker changes), in-task evaluation (non-comparable scores) |
| D3 | LLM returns the **complete corrected file**, never a diff | Models mangle diff syntax; the gate diffs original-vs-returned deterministically anyway |
| D4 | Rounds configurable (`ROUNDS`, default **3** total LLM calls); every retry is fed the measured patch size vs the budget | Self-hosted calls are free, and a stingy cap under-reports the rescue rate (records "unfixable" when the model was merely sloppy). The cap remains the cost ceiling for paid providers |
| D5 | Batch target selection: `SCOPE=latest` (default — latest submission per (user, problem) scoring below full marks) or `SCOPE=all`; `MIN_SCORE`/`MAX_SCORE` for score-stratified runs | Default cuts volume 10–20×; full-contest and stratified studies stay possible. Caveat: `SCOPE=all` multiplies *sandbox grading* load — LLM calls are free, judge time is not |
| D6 | **Self-hosted models are the default providers** — `qwen3.5` (DGX swap slot) and `gemma-4-31b` (always-on A100 box); ChulaGenie secondary | Marginal API cost ≈ 0 — this *is* the cost strategy; two free models also enable qwen-vs-gemma comparison studies |
| D7 | Interaction model of the eventual student-facing feature (staged ladder vs one-click AI repair vs mode-split) **deferred** until batch data exists | Owner decision ("decide this later; I want to learn which pedagogy is good first") — the batch instrument must not silently pre-decide it |
| D8 | **Viva submissions are excluded** from target selection (as dataset rejudge already does) | The budget is only a valid mechanical/conceptual proxy for *code*: in natural language a tiny edit ("O(n)" → "O(lg n)") is a conceptual change, and transcript re-grading has no deterministic ground truth |

## 5. Data model

### 5.1 New table `submission_repairs` — one row per attempt, including failures

| Column | Type | Notes |
|---|---|---|
| `original_submission_id` | FK → submissions, indexed, required | |
| `repaired_submission_id` | FK → submissions, nullable | set only when the gate accepts; the shadow submission |
| `status` | string/enum | `pending → processing → accepted \| over_budget \| no_change \| error` |
| `patch` | text | normalized unified diff **we** computed (display/analysis) |
| `changed_lines`, `changed_chars` | int, nullable | measured by the gate (null when no parseable file returned) |
| `budget_lines`, `budget_chars` | int | budget in force at generation |
| `rounds_used` | int | ≤ the run's `ROUNDS` cap |
| `rounds_log` | text (JSON) | per-round `{changed_lines, changed_chars, gate}` — powers budget-compliance analysis per model per round |
| `fix_category` | string, nullable | LLM self-report, validated against `io_format \| parsing \| syntax \| boundary \| logic \| other`; invalid ⇒ `other` |
| `llm_model` | string | |
| `token_count_in`, `token_count_out` | int | from `usage`; reasoning tokens count in `completion_tokens` |
| `cost` | float | dollars; 0.0 for Qwen but tokens still recorded |
| `llm_response` | mediumtext | raw final response body, for auditing |
| `remark` | text, nullable | LLM's one-sentence reason / error detail |
| `run_label` | string, indexed | groups a batch run; makes budget experiments comparable |
| timestamps | | |

Grading state and score of the repaired code live on the shadow `Submission`
row — **not duplicated here**. Reports join.

Status meanings: `accepted` = gate passed, shadow created and sent to judge;
`over_budget` = LLM produced code but every round exceeded budget;
`no_change` = normalized sources identical or LLM declared it unfixable within
budget; `error` = LLM/transport failure after job retries.

### 5.2 `submissions` gains `repaired_from_id`

Nullable self-referencing FK, indexed. Presence = shadow submission.

- New scope **`Submission.regular`** = `where(repaired_from_id: nil)`.
- **Rule: every student-visible query and every quota count reads
  `Submission.regular`.** Known sites to audit during implementation (the plan
  greps exhaustively): MainController list/max-score rollups
  (`prepare_list_information`), SubmissionsController index cost rollup,
  contest scoring reports (`Contest`, `ReportController` scoreboards),
  plagiarism/submission comparison, the viva daily-start-limit count
  (`viva_sessions_controller`), per-problem submission stats.
- Shadow submissions are **admin-visible only** in v1 (`can_view_submission?`
  denies students for shadows; simplest: shadows fail the ownership check by
  policy, since students should not discover the instrument through the UI).

Linkage is written twice — `repaired_from_id` on the shadow row and
`repaired_submission_id` on the attempt row — created in the **same
transaction** so they cannot drift.

### 5.3 Shadow submission semantics

Created via direct model create (no controller policy checks): same `user`,
`problem`, `language`; `source` = patched full file; `submitted_at` = creation
time (harmless — shadows are excluded from window-scoped queries);
`repaired_from_id` = original. Graded through the standard
`add_judge_job`-style path at **batch priority, below interactive rejudge**
(rejudge uses −10, dataset rejudge −50; near-miss uses a lower priority still —
exact value fixed in the plan after reading the priority ordering).

## 6. Budget gate (deterministic, LLM-free)

Pure service `SubmissionRepair::Gate` — heavily unit-tested; no I/O, no LLM.

1. **Normalize** both sources: CRLF/CR → LF; strip trailing whitespace per
   line; ensure single trailing newline. Nothing else (no comment stripping,
   no reindentation — keep it explainable).
2. **Diff** with `diff-lcs` (add as an explicit runtime dependency; today it is
   only a transitive RSpec dep), producing unified hunks. `patch` column stores
   this diff.
3. **Measure:**
   - `changed_lines`: per hunk, pair deletions with additions in order; a
     paired (delete, add) counts as **1 modified line**; unpaired lines count
     1 each. Hunk contribution = `max(deletions, additions)`; sum over hunks.
   - `changed_chars`: for each paired line, the character-level Levenshtein
     distance between the two normalized lines; for unpaired added/deleted
     lines, the full normalized line length. Sum over hunks.
4. **Accept** iff `changed_lines ≤ budget_lines` **AND**
   `changed_chars ≤ budget_chars`.
5. Identical normalized sources ⇒ `no_change`.

## 7. LLM service layer (viva registration pattern)

### 7.1 `Llm::SubmissionRepairAssist < Llm::Request` (abstract)

- `prepare_data` builds the prompt from:
  - problem statement PDF part (`encode_pdf_part`, as `CommentAssist` does);
  - original source (wrapped with the existing prompt-injection defense
    framing — source is untrusted input);
  - human-readable verdict: per-testcase results decoded from
    `grader_comment`, compiler output when the submission failed to compile;
  - the budget, stated explicitly ("you may change at most N lines and M
    characters");
  - output contract: *return the complete corrected file* in a fenced block,
    plus one category token from the `fix_category` enum and one sentence of
    reason. If no within-budget fix exists, say so explicitly (⇒ `no_change`).
- `handle_response`: extract file → `Gate` → on accept, one transaction
  creates the shadow submission + marks the row `accepted`; on gate rejection
  (or unparseable output, per §10), retry with the measured size vs the budget
  appended ("your patch changed 34 chars; the budget is 20"), up to the run's
  `ROUNDS` cap (default 3 total calls); exhaustion ⇒ `over_budget`. Every
  round's measurement lands in `rounds_log`.
- `compute_cost(usage)` — viva-style token/cost extraction.
- Abstract hooks per the existing pattern: subclasses supply `provider_name`,
  `execute_call(data)`, cost rates, `DEFAULT_MODEL`.

### 7.2 Concrete providers & registration

- `Llm::SubmissionRepairSelfHostAssist` (default) — one class serving all
  self-hosted models; the model key (any key of the `self_hosted_models:` map,
  e.g. `qwen`, `glm`, `kimi`, `gemma`) comes from the rake `SERVICE=`
  parameter, falling back to `self_hosted_default` — and
  `Llm::SubmissionRepairGenieAssist`.
- Registered via a new `submission_repair_service:` key in `config/llm.yml`
  (same pattern as `viva_turn_service:`), overridable per-run by the rake
  `SERVICE=` parameter (any self-host map key → SelfHost, `genie` → Genie).

### 7.3 `Llm::SubmissionRepairJob < Llm::RequestJob`

Standard retry taxonomy inherited; `on_retries_exhausted` marks the
`SubmissionRepair` row `error` so nothing freezes in `processing`.

## 8. Self-hosted transport & submission-assist provider (second feature)

### 8.1 `Llm::SelfHostChat` — shared transport

OpenAI-compatible `POST {base_url}{completion_path}` (`/v1/chat/completions`),
JSON, **no auth** (intranet-only DGX), via the existing Faraday factory
(`Llm::Request.connection`, 300s timeouts — comfortably above the 120s the
reasoning models need). Ported lessons from cp-api
(`~/cp-api/docs/llm-api.md`, `llm_service.rb#chat_completion`):

- **omit `repetition_penalty`** (degrades reasoning traces);
- **`max_tokens ≥ 4096`** (reasoning tokens count against the budget; small
  budgets yield empty `content`);
- tolerate `reasoning_content` in responses; answer text is
  `choices[0].message.content`;
- extract `usage.prompt_tokens` / `usage.completion_tokens`;
- connection refused / host unreachable is **normal operation** for a
  swapped-out DGX slot (ports 8000–8002 share GPUs; exactly one is alive) —
  classify as retryable connection error, never as a code bug;
- the A100 box (`gemma-4-31b`) is always-on and **validates** model names,
  while the DGX merely echoes them — a wrong model string fails only on gemma,
  so test against it.

**Naming principle: model identity is config data, never code.** No class,
method, or column name references a specific model; the `self_hosted_models:`
keys are operator-chosen labels. Adding, swapping, or renaming a model is a
one-entry `llm.yml` edit with zero code change.

Config sketch (real values on `chula_cp`; blank/commented on `master`, same
convention as the viva service keys; no credentials involved):

```yaml
llm_services: &services
  # …existing keys…
  SelfHostAssist: qwen3.5,gemma-4-31b        # served-model names shown in the assist picker
  submission_repair_service: Llm::SubmissionRepairSelfHostAssist
  self_hosted_default: qwen
  self_hosted_models:                        # keys are labels, not code
    qwen:  { base_url: "http://<dgx>:8000",  completion_path: "/v1/chat/completions", model: "qwen3.5",     max_tokens: 4096 }
    glm:   { base_url: "http://<dgx>:8001",  completion_path: "/v1/chat/completions", model: "glm-5.2",     max_tokens: 4096 }
    kimi:  { base_url: "http://<dgx>:8002",  completion_path: "/v1/chat/completions", model: "kimi-k2.6",   max_tokens: 4096 }
    gemma: { base_url: "http://<a100>:8000", completion_path: "/v1/chat/completions", model: "gemma-4-31b", max_tokens: 4096 }
```

All three DGX swap residents are listed even though at most one is live —
a swapped-out entry simply refuses TCP, which the transport already treats as
a clean retryable error, and `SERVICE=` against it fails fast with a clear
message rather than misrouting.

**Model-identity guard:** the DGX echoes the payload `model` string without
validating it, so a redeployed port could silently answer as a different model
— fatal for run comparability. The batch runner therefore calls
`GET <base_url>/v1/models` once at startup and **aborts on mismatch** between
the served model id and the configured `model`. (The A100 box validates
per-request anyway.) `llm_model` on each attempt row records the verified
served name.

### 8.2 `Llm::SelfHostAssist < Llm::CommentAssist`

Submission-assist provider using the shared transport. Registered in the
per-model provider map: `SelfHostAssist: qwen3.5,gemma-4-31b` in
`llm_services` — one class serving both models, exactly the existing
`GenieAssist: gemini-2.5-pro,Claude-Sonnet` precedent — which makes them
appear in the existing assist model picker. **Known quirk to respect:** the
`llm_assist` route addresses models by *index* into
`Rails.configuration.llm[:provider].keys`, and
`_add_assist.html.haml` hardcodes `cost: 10` — the plan must verify adding
models does not silently shift existing indices in views/links. Dollar cost
for self-hosted models is 0.0; token counts are still recorded
(`compute_cost` returns 0 with usage logged).

## 9. Batch runner & report

### 9.1 `rake near_miss:repair`

```
rake near_miss:repair CONTEST=<id> [PROBLEM=<id>] [SUBMISSION=<id>]
     [SCOPE=latest|all] [MIN_SCORE=<n>] [MAX_SCORE=<n>]
     [BUDGET_LINES=2] [BUDGET_CHARS=20] [ROUNDS=3]
     [SERVICE=<self-host key>|genie] [RUN=<label>] [LIMIT=<n>] [DRY=1]
```

- Target selection: `SCOPE=latest` (default) takes the latest submission per
  (user, problem) within the contest scoring below full marks — including
  compile errors; `SCOPE=all` takes every below-full submission.
  `MIN_SCORE`/`MAX_SCORE` bound the original score for stratified runs (e.g.
  a zeros-only run vs a 1–99 run under different `RUN` labels). Always
  `Submission.regular` only (never repair a shadow), and viva-language
  submissions are always excluded (D8).
- `DRY=1` prints target count + breakdown and exits. `LIMIT` caps targets for
  pilot runs. `RUN` defaults to a generated label (`contest<id>-<date>`).
- Enqueues one `Llm::SubmissionRepairJob` per target; Solid Queue's queue
  concurrency naturally throttles the DGX. Attempt rows are created `pending`
  up front so a crashed run is enumerable and resumable (re-run skips
  submissions that already have a row with the same `run_label`).

### 9.2 `rake near_miss:report RUN=<label>[,<label>…]` (or `CONTEST=<id>`)

Per-problem table: targets, attempts by status, repaired-and-improved count,
**rescue rate** (fraction of below-full targets whose shadow scored higher),
mean/median mechanical gap, fix-category histogram, distribution of measured
repair sizes (which shows how much of the budget real fixes actually used),
and **budget compliance** — per model, per round, from `rounds_log`: how often
the returned patch was actually within budget (the gate verifies every patch
deterministically; this reports how often each model needed correcting).
Plus a run-level cost line: total tokens in/out, dollar cost, LLM rounds.

Passing multiple `RUN` labels renders the runs **side-by-side** — the
comparison view for budget experiments, qwen-vs-gemma-vs-genie, and score
bands. Console table + CSV export (path printed).

## 10. Error handling

- Transport/HTTP errors follow the existing `RequestJob` retryable taxonomy;
  exhaustion ⇒ row `error` with the exception in `remark`.
- Unparseable LLM output (no fenced file found) consumes a round like a gate
  rejection (the retry says so); exhausting all rounds without ever getting a
  parseable file ⇒ `error` with raw body stored (`over_budget` is reserved for
  parseable-but-too-large outcomes).
- The gate itself cannot fail soft: any exception there is a bug and should
  raise loudly (no rescue).
- Shadow-submission grading failures are ordinary judge errors, visible on the
  shadow row like any submission; the report counts them separately.

## 11. Testing

Written after the feature (owner's stated preference), all minitest:

- **Gate:** heavy pure-function coverage — pairing rules, both caps,
  normalization, no-change, unparseable input.
- **Scopes:** `Submission.regular` exclusion asserted at each audited site
  (model/controller level).
- **Service:** `handle_response` paths (accept/over-budget/retry/no-change/
  garbage) with a stubbed transport; transaction atomicity of shadow+row.
- **SelfHostChat:** request-shape (omitted `repetition_penalty`, `max_tokens`
  floor) and response parsing incl. `reasoning_content`, via stubbed Faraday.
- **Rake:** target-selection query + DRY mode smoke test.

## 12. VCS & deployment notes

- All commits on **`master`** (bookmark-gated per standing convention);
  `chula_cp` receives via the usual batch merge. `llm.yml` service keys and
  self-hosted endpoints get real values on `chula_cp` during the merge,
  mirroring the viva-keys convention.
- CHANGELOG: one `### Added` bullet (instructor-facing capability) in the
  same commit series.
- **Provider placement** (`doc/decisions.md` 2026-07-30): generality decides
  the branch — the SelfHost classes are generic (any OpenAI-compatible
  endpoint) and live on **master**; `Llm::GenieAssist`/`Llm::TokenManager`
  exist only on `chula_cp` (verified during planning — the earlier assumption
  that they were on master was wrong), so
  `Llm::SubmissionRepairGenieAssist` is a small **chula_cp-side follow-up**
  (backlogged), not part of this master-side build.

## 13. Future work (explicitly out of scope, recorded so it isn't relitigated)

- Student-facing surface: staged ladder (hand-edit within budget → "a fix
  exists near X" hint → show diff → apply), lifeline economy via the existing
  `comments.cost` machinery, mode-split behavior — **to be chosen from the
  batch data**.
- Naming of the student surface ("Second Chance" / "Lifeline").
- `GraderConfiguration` keys for admin-editable default budgets; per-problem
  budget overrides.
- Web report page under `/report`; budget-curve experiments via multiple
  `run_label`s.
- Practice-mode feedback surface ("your code is 12 chars from passing").
- **OpenRouter provider** (design sketch in `doc/backlog.md`): a master-side
  sibling transport sharing the OpenAI-compatible payload/parse with
  `SelfHostChat`, adding Bearer auth (key in Rails credentials) and real
  `compute_cost`. Deliberately a separate transport + separate `llm.yml`
  section rather than extra fields on `self_hosted_models:`, so the
  self-host invariants (no auth, cost 0, identity guard) stay explicit.
