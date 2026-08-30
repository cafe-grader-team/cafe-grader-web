# Viva Deployment Readiness — Design

**Date:** 2026-07-20
**Status:** Approved design, ready for implementation plan
**Area:** Viva exam (`app/services/llm/viva_*`, `Problem`, `Tag`, `GroundingMaterial`, `VivaSessionsController`)

## Context & goals

Timeline: a **practice month for a full course starting August 2026**, then a
**graded exam (~October 2026)** with **100–200 students running vivas
concurrently** against the Chula Genie relay (Gemini 2.5 Flash). This design
makes viva survivable for both phases.

Guiding principle (from brainstorming): **build what the calendar forces;
instrument what is unmeasured; defer what is hypothetical.**

### Evidence triage — why these features and not others

- **Proven / scheduled:** retake mechanism (practice month collides with the
  single-attempt-until-admin-archive policy on day one), turn caps and
  throughput (forced by 100–200 concurrency).
- **Mechanism certain, magnitude unknown → instrument:** token/latency load
  (beta data already sits in `viva_turns`; query it), jailbreak
  false-positive/negative rates (zero data; the practice month *is* the
  measurement instrument).
- **Hypotheses with cheap fixes → do the cheap part:** PDF↔prompt misalignment
  (no observed incident, but converted paper exams carry embedded
  rules-of-engagement text — a concrete vector), authoring confusion (n=1 beta
  tester, but the code-confirmed mislabeled description field costs almost
  nothing to fix).
- **Cost math honesty:** at Flash pricing (~$0.30/M input) even a worst-case
  180k-token session is ~$0.05; dollars are *not* the driver. The real stakes
  of re-sending PDF bytes every turn are per-turn latency, unknown relay
  quota at exam concurrency, and attention dilution across a whole deck.

## D1 — Practice/exam mode

New per-problem setting `Problem#viva_mode` enum `{ exam: 0, practice: 1 }`,
flippable anytime (never an exclusive classification).

- **Default: `exam`** — the fail-safe direction; a forgotten `practice` toggle
  inside a real exam would permit restarts.
- UI: problem form (viva section) + a **read-only "practice" badge** on the
  problems index for viva rows in practice mode. *(Amended 2026-07-21, dae's
  call: originally a per-row switch, but with `exam` as the birth default and
  exam vivas authored fresh, the mass-flip workflow never materializes — the
  index need is at-a-glance visibility, and a badge has no misclick risk on an
  exam-integrity setting. Flipping stays on the form, next to the guard.)*
- **Forgotten-toggle guard:** prominent warning on the problem form and the
  contest page when a `practice`-mode viva is attached to an active contest.
- Recorded caveat (instructor's content decision, not platform-enforced):
  flipping practice→exam on the same problem means students have seen that
  scenario.

## D2 — Retakes

- **Practice:** student-facing **Restart** button archives their own submission
  (reuses `viva_archived_at`), rate-limited (default **3 starts per problem per
  day**) to bound cost and discourage examiner-grinding.
- **Exam:** unchanged — single attempt; admin archive resets.

## D3 — Jailbreak policy: detect in the prompt, decide in the backend

The current one-shot irreversible in-prompt termination is replaced by a
split:

- **Prompt (detect-only):** the security directive tells the examiner to emit
  `[[VIVA_ALERT]]` when it detects an attempt but **stay in character and
  continue**. No in-prompt state machine (models are unreliable at remembering
  they already warned).
- **Backend (policy):** strips the sentinel, records an alert flag on the turn,
  counts strikes per submission:
  - **Practice:** log + show the student a gentle notice; never terminate.
  - **Exam:** strike 1 → formal recorded warning injected as a visible
    system-role turn in the transcript;
    strike 2 → terminate (`viva_terminated_at`, grading proceeds as today with
    the existing `termination_note` behavior).
- **Alert-review admin page:** flagged sessions with transcripts — the
  calibration instrument for the practice month.
- **Red-team regression set:** scripted attacks + benign-but-edgy utterances,
  replayed via a manual rake task whenever the prompt or policy changes.
- Accepted trade-off: warn-first gives one free probe (a boundary oracle);
  chosen deliberately as false-positive insurance — at 200 students, a 1% FP
  rate is two wrongly-terminated exams.

## D4 — Grounding: PDF → text extraction (committed, not conditional)

New **“Extract text”** action on a `GroundingMaterial`:

- A one-shot multimodal LLM job renders the attached PDF into a markdown
  **draft in the existing editable `body` field** — faithful-but-compact:
  boilerplate condensed, technical content preserved, figures described
  briefly. (A true-summary prompt variant is a possible later per-material
  option, not in scope.)
- **Author review is mandatory** — the draft is never silently saved; Thai
  slide extraction is too lossy to trust blind. The author edits, then saves.
- **Send-time rule, per material:** `body` present → send the text, skip the
  PDF bytes; `body` blank → send the file (today's behavior).
- `estimated_tokens` recomputes on save.

## D5 — Scenario authoring

For `viva_exam` problems only:

- Description tab relabeled **“Scenario (markdown) — sent verbatim to the
  examiner”** (the field already feeds `scenario_message`; this makes the
  existing wiring discoverable). The auto-generated PDF-export panel is hidden.
- Statement PDF stays supported, demoted: *“attach only when the scenario
  needs figures or original exam layout.”* Both are sent when both exist; the
  scenario text is authoritative.
- **Security-boundary framing** (labels + authoring guide): scenario = the
  exam paper (nothing secret; could be shown to students post-exam);
  `viva_prompt` = the marking scheme + examiner's private briefing (never
  shown). Channel contract: **conduct tag = how to examine; `viva_prompt` =
  rubric/answers; scenario = the case; PDF = figures.**

## D6 — Prompt home & final tag taxonomy

Per-problem secret content moves out of tags; the shared layer stays in tags
under a dedicated kind.

```ruby
enum :kind, { normal: 0, topic: 1, llm_prompt: 2, viva_conduct: 3 }
```

| Kind | Meaning | Consumer | `public` | Format rule |
|---|---|---|---|---|
| `normal` | plain label | UI filtering | author's choice | none |
| `topic` | semantic grouping | UI filtering | author's choice | none |
| `llm_prompt` | AI-helper ("Codey") system prompt | `Llm::CommentAssist` **only** | **forced `false`** | none |
| `viva_conduct` | shared examiner persona/conduct | viva assembly **only** | **forced `false`** | none (loose prose) |

- **New column `problems.viva_prompt`** (text): rubric + model answers +
  problem-specific examiner guidance. Secret; added to Problem's `audited`
  whitelist **with `redact:`**. The `# Rubric` requirement moves here
  (`viva_setup_errors` requires a non-blank `viva_prompt` containing
  `# Rubric`; a conduct tag becomes optional, expected 0–1).
- **Assembly order, fixed and deterministic:** `viva_conduct` tags
  (`order(:name)`) → `viva_prompt` → backend `SECURITY_DIRECTIVE` →
  done-sentinel directive.
- **`Llm::CommentAssist` untouched** — `llm_prompt` now unambiguously means
  "helper prompt". This closes a real latent collision: both features read
  `kind: llm_prompt` today, so a bulk-tagged tutor persona would silently
  concatenate into an examiner's system prompt (and vice versa).
- **Tag model:** validation forcing `public = false` for both LLM kinds (form
  hides the checkbox for them); "used by N problems" count on the edit form.
- **Problem form:** viva section gains a **Conduct profile** select2 (like the
  grounding select); the generic tag widget stops offering **`viva_conduct`**
  tags (one dedicated path for conduct) but **keeps offering `llm_prompt`**.
  *(Amended 2026-07-21, dae's call: hiding `llm_prompt` silently stripped
  helper tags on every save — `tag_ids=` is whole-collection replacement and
  the picker is the helper's only attach UI. Contamination is instead
  prevented at the consumer layer: viva reads only `viva_conduct` +
  `viva_prompt`; CommentAssist reads only `llm_prompt`. Rationale in
  `doc/decisions.md` 2026-07-20 entry.)*
- **Migration (one script + printed report):**
  1. Add enum value + column (additive, safe).
  2. Classify each viva problem's `llm_prompt` tags:
     - attached to exactly one problem (pseudo-tag) → copy `params` into that
       problem's `viva_prompt`, detach, delete the tag;
     - attached to multiple viva problems (genuinely shared, e.g. `ai_viva`) →
       re-kind to `viva_conduct`, force `public: false`; report if it contains
       a `# Rubric` section (author decides: generic rubric stays in conduct
       or is copied per-problem);
     - attached to both viva and non-viva problems (dual-use) → **report only,
       manual split** — the script must not guess.
  3. Post-check: every viva problem passes the new `viva_setup_errors`.
- **Rationale to record in `doc/decisions.md` at implementation time:**
  *ownership follows cardinality* — per-problem content lives in columns,
  cross-problem content in shared entities; `Tag` returns to labels plus
  legitimately-shared staff-only text; a unified "LLM asset" entity stays
  rejected (2026-07-19 grounding design, reaffirmed today). Entity behavior
  divergence (files/tokens/extraction vs. prompt text vs. public labels)
  justifies separate models; the thing worth unifying is the UI pattern
  (library + select2 + token badge + used-by count), not the table.

## D7 — Authoring validation: lint + test-drive (one workflow)

- **Test-drive (primary validation):** the author takes the viva themselves in
  a session flagged as a test — excluded from reports, cost dashboards, and
  attempt limits; unlimited restarts regardless of mode. Empirical behavior is
  the only real check of an LLM examiner.
- **Preflight lint (advisory pre-check):** an LLM pass over the **assembled
  prompt exactly as the examiner receives it** (conduct tags + `viva_prompt` +
  scenario + statement PDF + grounding + `SECURITY_DIRECTIVE`), returning a
  JSON report. **High-precision checks only** — the first false-alarm-heavy
  lint teaches authors to ignore it:
  - rubric/model-answer leakage into student-visible channels,
  - cross-channel conduct contradictions (including author text contradicting
    the security directive),
  - missing `# Rubric`, banned `{{…}}` template literals,
  - more than one conduct tag attached (smell, not error),
  - **embedded operational instructions in briefing/conduct text** — alert
    rules, output-format demands, termination rules written for the LLM
    (platform owns all of these). *Not hypothetical: on 2026-07-21 a migrated
    legacy briefing carried its own `----- ALERT -----` rule; the grader
    obeyed it over the JSON contract and the submission failed with
    grader_error. The grading prompt now inoculates against this, but lint
    must flag the content itself.*
  Lint predicts text conflicts, never model behavior — it makes test-drives
  less wasteful, it does not replace them.
- **Shared-tag blast radius:** editing a `viva_conduct` tag warns "used by N
  viva problems" and nudges re-lint/re-test-drive of affected vivas.

## D8 — Turn caps

Per-problem **soft cap** (default 10): the assembled prompt instructs the
examiner to complete within ~N questions and wrap up. Per-problem **hard cap**
(default 15): at M student turns the backend forces evaluation exactly as if
`[[VIVA_DONE]]` had been emitted. Insurance against stalls, runaway sessions,
and long-transcript grading decay.

## D9 — Measurement & ops

1. One-off query of beta `viva_turns` (tokens/turn, turn latency, session
   shapes) → informs cap defaults and extraction tuning.
2. Prefix-caching experiment: does Gemini's implicit prefix caching survive
   the Genie relay? (Message assembly is already prefix-stable; free win if it
   passes through.)
3. Genie load test at exam concurrency, before October.
4. Slide-discipline norm added to the course-prep authoring guide: *attach the
   slides the scenario actually needs, not the whole deck* — highest
   leverage-per-effort token fix, zero code.
5. Stuck-turn monitoring (`stuck_viva_turns`) unchanged.

## Out of scope (decided, not forgotten)

- RAG over grounding (overkill at slide-deck scale).
- Structured `VivaScenario` rebuild (out of proportion on this runway; D6 is
  forward-compatible with it).
- Per-attempt scenario variation.
- Grade moderation queue — **grades keep showing immediately** (decided);
  the existing admin regrade-with-model-picker is the dispute safety valve.
- Grounding image-file support (stays in backlog).

## Phasing

- **Phase 1 (before August):** D1, D2, D5, D6, D8, plus the alert-recording
  backend of D3.
- **Phase 2 (during the practice month):** alert-review page, D4 extraction,
  D7 lint + test-drive, D9 measurements.
- **Phase 3 (before the exam):** load test, red-team pass, then feature freeze
  on the viva path.

## Risks acknowledged

| Risk | Position |
|---|---|
| Practice mode as jailbreak gym / examiner-gaming rehearsal | Accepted: probing happens anyway; better observed than discovered in the exam. Mitigated by restart rate limit + attributable alert logs. |
| Warn-once = one free probe (boundary oracle) | Accepted, for false-positive insurance at exam scale. |
| Extraction fidelity loss (Thai slides, formulas, figures) | Mitigated: draft-only, mandatory author review, per-material opt-in. |
| Lint alarm fatigue → ignored lint | Mitigated: high-precision check list only; lint is advisory, test-drive is primary. |
| Forgotten mode toggle in a real exam | Mitigated: `exam` default + active-contest warning banner. |
| September features debugged in October's exam | Mitigated: Phase 3 feature freeze. |
