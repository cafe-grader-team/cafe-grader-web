# Viva Phase 1 — Overnight Execution Report (2026-07-20 → 07-21)

**Status: COMPLETE.** All 9 plan tasks executed, per-task reviewed, final
whole-branch review passed (READY-WITH-FIXES → fixes applied). 13 commits on
`master`, revs **1878–1890** (base: 1877, the plan commit). Nothing pushed, no
`chula_cp` merge, no live LLM calls, migration NOT applied (report-only).

## What landed

| Revs | Task | Delivered |
|---|---|---|
| 1878 | T1 | Schema + models: `problems.viva_mode/viva_prompt/viva_soft_cap/viva_hard_cap`, `viva_turns.alerted`, `Tag` kind `viva_conduct` (+ `public=false` coercion for LLM kinds), audited w/ redaction |
| 1879 | T2 | Prompt assembly: conduct tags → `viva_prompt` → security → directives; `viva_setup_errors` on the column; `viva_prompt_tags` deleted; CommentAssist untouched (verified zero-diff) |
| 1880–1881 | T3 | `viva:migrate_prompt_tags` rake (report-first; APPLY=1 gated) + CONFLICT guard |
| 1882–1883 | T4 | Alert backend: detect-only directive, backend strike policy (practice logs / exam warn-then-terminate), system turns now student-visible |
| 1884 | T5 | Turn caps: soft pacing directive + hard force-finish in `answer` |
| 1885 | T6 | Practice⇄exam radio + guard alert (form), practice-viva badge on contest problems table (via DataTables JSON) |
| 1886 | T7 | Practice self-restart + 3/day rate limit (admin-exempt) |
| 1887–1888 | T8 | Authoring UI: "Scenario (markdown)" relabel, examiner-briefing/conduct/caps inputs, PDF-export demoted for vivas, tag-form hygiene, 4 stale help texts |
| 1889–1890 | T9 | Comment cleanup + final-review fix wave (below) |

**Final gate:** full `bin/rails check` green at the branch tip (rev 1890):
**667 minitest / 1598 assertions / 0 failures / 0 errors** (5 pre-existing
skips) + **124 RSpec examples / 0 failures** + swagger fresh. Rubocop/brakeman:
no new offenses/warnings.

## What the review process caught (the night's real value)

1. **T3 CRITICAL (plan-authored):** migrator MOVE silently overwrote an
   existing `viva_prompt` — unrecoverable, since the source tag is destroyed.
   Now a `CONFLICT … skipped` report line.
2. **T4 IMPORTANT:** system turns rendered admin-only — the strike-1 warning
   (the entire point of warn-first) was invisible to students. Fixed +
   empirically RED-verified test.
3. **T8 HIGH (spec-authored):** the spec's "generic picker stops offering
   LLM-kind tags" + Rails whole-collection `tag_ids=` = every ordinary save of
   a non-viva problem silently stripped its Codey tags. **Spec deviation
   applied** (see below).
4. **Final review IMPORTANT:** practice-era alert strikes carried into exam
   mode after a mid-session toggle flip → could terminate without any exam-era
   warning. Fixed: termination now requires a prior exam-warning turn on the
   submission (1890).
5. Final-review minors fixed in 1890: caps numericality validation (blank
   form → error, not 500), `restart` guards (`viva_exam?` + already-archived),
   `gsub` sentinel stripping, stale help-drawer line.

## ⚠️ Needs your sign-off (spec deviation)

The generic tag picker now excludes **only `viva_conduct`**; `llm_prompt`
remains offered (it's the AI-helper's only attach UI, and hiding it caused the
silent tag-stripping above). Contamination is prevented at the consumer layer
instead (viva reads only `viva_conduct` + `viva_prompt`; CommentAssist reads
only `llm_prompt`). The final reviewer judged the deviation sound. Rationale
recorded in `doc/decisions.md`. **The spec §D6 text still says otherwise —
amend it (or overrule the deviation) when you review.**

## Awaiting you (in order)

1. **Tag migration:** review the dry-run report — regenerate with
   `bin/rails viva:migrate_prompt_tags` — then run with `APPLY=1`. Dev DB has
   one MOVE (tag #37 `AI-VIVA` → `test_viva2`, 2938 chars); `test_viva` is
   flagged as missing a briefing (pre-existing gap, needs authoring).
2. **Batch-merge `master` → `chula_cp`** and run a live viva smoke test
   (Genie classes live there). Then run the migration on that DB too.
3. ~~Decide finding #3 of the final review~~ **RESOLVED 2026-07-21 (dae):**
   spec deviation confirmed (llm_prompt stays in the picker) and the index
   switch became a read-only "practice viva" badge — spec amended (rev 1892),
   badge shipped with tests (rev 1893).
4. Deferred minors (all triaged DEFER by the final reviewer): quote-style in
   two tests, theoretical concurrent at-cap double-enqueue (pre-existing
   pattern), DataTables unescaped `${data}` (pre-existing, admin-only —
   backlog note), restart re-stamp cosmetics, `viva_prompt` nil→"" churn on
   non-viva saves.

## Where everything is

- Ledger (per-task detail): `.superpowers/sdd/progress.md`
- Final review findings: scratchpad `final-review-findings.md`; gate evidence:
  `task-9-gate-report.md`; per-task briefs/reports/diffs: same scratchpad.
- Phase 2 (practice-month work: alert-review page, extraction, lint,
  test-drive, measurements) starts from the spec §11 when you're ready.
