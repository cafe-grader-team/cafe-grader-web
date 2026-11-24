# Deduction Cap and Spending Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A contest carries a deduction cap and an AI-help spending limit, the site carries a spending-limit setting, and every score, deduction, confirm box and refusal applies them.

**Architecture:** One Ruby module, `HelpDeduction` (`app/models/help_deduction.rb`), holds the rule and every lookup. Reports stop computing `final_score` in SQL; `Submission.calculate_max_score` computes it in Ruby with a `deduction_cap:`. The student list, the two confirm boxes and `Submission#llm_assist_refusal` read caps and limits through the same module.

**Tech Stack:** Rails 8, MySQL 8, HAML, simple_form, Stimulus/DataTables, Minitest.

**Spec:** `docs/superpowers/specs/2026-11-21-deduction-cap-spending-limit-design.md` (approved 2026-11-21).

**Execution note (dae, 2026-11-21 night):** build in the working copy on `master`, **no commits, merges, pushes or deploys** until dae says OK. Steps that say "commit" become "checkpoint: run the task's tests"; one commit per task is made after dae's OK.

## Global Constraints

- Names: **deduction cap** (`contests.deduction_cap`), **spending limit** (`contests.assist_spending_limit`, site key `system.llm_assist_spending_limit`). Never "hard cap" in code or UI.
- Rule: `deduction = cap.nil? ? hint + ai : min(hint + ai, cap)`; `final = max(0, min(raw best score, 100 - deduction))`.
- `deduction_cap`: integer 0..100, nullable. `assist_spending_limit`: integer >= 0, nullable. Site setting integer, value `100`.
- Spending limit counts AI help only (status `ok`, all time, by submission owner), stops new requests once `spent >= limit`.
- In contest mode, "lost so far" and contest reports count hints revealed inside the student's own window and AI help on submissions made in it.
- Seconds are added with `DATE_ADD/DATE_SUB(... INTERVAL n SECOND)`, never `ADDTIME`.
- One cap/limit lookup query per page, never per problem.
- No student data in tests or docs. hg, not git; explicit file lists.

## Review Focus

1. A student in contest mode with no running contest (between contests): list must render, no cap, no notice, nothing counted (empty `active_contests_range`). → Task 4 test "list in contest mode with no running contest".
2. Hint cost fractional (fixture `hint_for_add` costs 1.5): every displayed number formats without float noise. → Task 4 asserts "1.5".
3. A contest-scoped Best Score request that also carries `deduction_cap=` must use the contest's cap, not the param. → Task 2 test.
4. Spending limit 0: the picker refuses with a readable message, not "spent 0 of the 0". → Task 5 test.
5. Global box value out of range or junk (`abc`, `150`, `-5`): treated as no cap, page still renders. → Task 1 `parse_cap` test + Task 3 request test.

---

### Task 1: Rule module, columns, site setting

**Files:**
- Create: `app/models/help_deduction.rb`, `db/migrate/20261121150000_add_deduction_cap_and_assist_spending_limit_to_contests.rb`, `db/migrate/20261121150100_seed_llm_assist_spending_limit_configuration.rb`, `test/models/help_deduction_test.rb`
- Modify: `app/models/contest.rb` (validations, `audited only:`), `db/seeds.rb` (key after `system.llm_assist_cost`), `db/schema.rb` (by migrate), `test/fixtures/grader_configurations.yml` (`GraderConfiguration_31`)

**Interfaces — Produces** (module functions on `HelpDeduction`):
- `FULL_SCORE = 100`, `SPENDING_LIMIT_KEY = 'system.llm_assist_spending_limit'`, `DEFAULT_SPENDING_LIMIT = 100`
- `deduction(hint, ai, cap) -> Float`; `final_score(raw_score, hint, ai, cap) -> Float`
- `parse_cap(value) -> Integer|nil` (0..100 only)
- `site_spending_limit -> Integer`
- `running_contests_by_problem(user, problem_ids) -> {problem_id => [Contest]}` (via `user.active_contests`, `contests_problems.enabled`; `{}` outside contest mode)
- `cap_for(contests) -> Integer|nil` (the one shared value, else nil); `caps_disagree?(contests) -> Boolean`
- `spending_limit_for(contests) -> Integer` (max of `c.assist_spending_limit || site_spending_limit`, else site)
- `capped_problem_ids(user, problem_ids) -> Set` (enabled contests the user is in that set a cap)
- `losses(user, problem_ids) -> {problem_id => {hint_count:, hint_cost:, ai_count:, ai_cost:}}` (contest mode: within `user.active_contests_range`; counts nil and costs 0 when none)
- `ai_spent(user, problem_id) -> Numeric` (status `ok` llm_assist comments on the user's submissions of the problem, all time)
- `Budget` struct (`cap, contest_name, hint_lost, ai_lost, ai_spent, spending_limit`) with `lost`, `counted`, `counts(cost)`, `at_cap?`; `budget(user, problem) -> Budget`

- [ ] **Step 1: tests** in `test/models/help_deduction_test.rb`: `deduction(10, 15, nil) == 25`, `deduction(20, 25, 30) == 30`, `deduction(10, 5, 30) == 15`; `final_score(90, 20, 25, 30) == 70`, `final_score(90, 0, 0, 30) == 90`, `final_score(100, 60, 60, nil) == 0`; `parse_cap('30') == 30`, `parse_cap('') / 'abc' / '150' / '-5' / nil` all nil, `parse_cap('0') == 0`; `site_spending_limit == 100` from the fixture, `150` after `set_grader_config('system.llm_assist_spending_limit', 150)`; `cap_for([c30, c30]) == 30`, `cap_for([c30, c20]) nil`, `cap_for([cnil, c30]) nil`, `cap_for([]) nil`; `spending_limit_for([]) == 100`, `[nil-limit, 150] == 150`, `[50] == 50`; Contest validations (`deduction_cap` 101 / -1 / 1.5 invalid, nil and 30 valid; `assist_spending_limit` -1 invalid, 0 and 250 valid); the seed migration run twice leaves one row whose value an operator changed is untouched.
- [ ] **Step 2: run, expect failures** — `bin/rails test test/models/help_deduction_test.rb`
- [ ] **Step 3: implement.** Migration adds two nullable integer columns. Seed migration copies `SeedLlmAssistCostConfiguration` (idempotent, `value_type: 'integer'`, value `'100'`, description from the spec's Database section). Contest: `validates :deduction_cap, numericality: {only_integer: true, in: 0..100}, allow_nil: true`; `validates :assist_spending_limit, numericality: {only_integer: true, greater_than_or_equal_to: 0}, allow_nil: true`; both columns join `audited only:`. `running_contests_by_problem`: `user.active_contests.joins(:contests_problems).where(contests_problems: {problem_id:, enabled: true}).select('contests_problems.problem_id AS cp_problem_id').group_by(&:cp_problem_id)`. `losses` moves the two queries out of `MainController#prepare_list_information` (AI: `Submission.regular.where(user:, problem_id:)[.where(submitted_at: range)].with_llm_stat_by_problem`; hints: `Problem.joins(comments: :comment_reveals).where(id:, comment_reveals: {user:[, created_at: range]})`). `Budget#counts(cost)` = `cap.nil? ? cost : min(max(cap - counted, 0), cost)`.
- [ ] **Step 4: run `bin/rails db:migrate` and the tests, expect pass.**

### Task 2: Reports apply the cap; contest hints use each student's window

**Files:**
- Modify: `app/models/submission.rb` (`max_score_report` drops its `final_score` select; `calculate_max_score` gains `deduction_cap: nil`), `app/models/contest.rb` (`score_report` drops its `final_score` select, uses the new hint scope, passes `deduction_cap:`), `app/models/comment.rb` (scope), `app/controllers/report_controller.rb` (`max_score_query` global path), `app/javascript/controllers/datatables/init_score_table_controller.js` (copy `raw_cost_*`, "(cap)" label)
- Test: `test/models/submission_test.rb`, `test/models/contest_test.rb`, `test/integration/report_contest_scope_test.rb`

**Interfaces:**
- Consumes: `HelpDeduction.final_score`, `.deduction`, `.parse_cap`
- Produces: `Submission.calculate_max_score(records, users, problems, with_comments: true, deduction_cap: nil)` — per problem also emits `raw_cost_<id>` (uncapped hint + AI) beside `total_cost_<id>` (counted deduction). `Comment.hint_reveal_in_contest_windows(contest, problems)` — same columns/grouping as `hint_reveal_for_problems`, window per member: `comment_reveals.created_at` between `DATE_SUB(contest.start, INTERVAL IFNULL(cu.start_offset_second,0) SECOND)` and `DATE_ADD(contest.stop, INTERVAL IFNULL(cu.extra_time_second,0) SECOND)`, joining `contests_users` of that contest on the reveal's user.

- [ ] **Step 1: tests.** submission_test: rewrite "max_score_report floors final_score at zero…" to assert through `calculate_max_score` (final 0, total_cost 120); new: with `deduction_cap: 30` and AI 60 on a 90-point submission → `final_score_<id>` 70, `total_cost` 30, `raw_cost` 60. contest_test: `score_report` with `deduction_cap` 30 and AI 45 + hint → final = min(raw, 70); floor at 0 without a cap (AI 150); a hint revealed during james's extra time (stop 5 min ago, extra 660) counts; a hint revealed a day before start does not. report_contest_scope_test: Best Score with `contest` and `deduction_cap=0` uses the contest's cap (30), and equals Watch; global Best Score with `deduction_cap=30` caps.
- [ ] **Step 2: run, expect failures.**
- [ ] **Step 3: implement** as the Interfaces say. JS: in `processScore` copy `raw_cost_${prob.id}`; in `_deduction_renderer_factory` start from `let st = (parseFloat(row[\`raw_cost_${prob_id}\`]) > parseFloat(data)) ? \`${data} (cap)\` : \`${data}\`` for both branches.
- [ ] **Step 4: run the three test files plus `test/models/ai_usage_report_test.rb`, expect pass.**
- [ ] **CHANGELOG** `### Fixed`: hints revealed during a student's extra time now count on Watch and contest Best Score; Watch no longer shows negative scores.

### Task 3: Staff UI — contest fields, Best Score box

**Files:**
- Modify: `app/views/contests/_form.html.haml` (two inputs after `enabled`), `app/controllers/contests_controller.rb` (`contests_params`, `clone`), `app/views/contests/show.html.haml` (two `key_pair`s in Contest Detail), `app/views/report/max_score.html.haml` (box + `extra_hint`), `app/views/report/_contest_scope.html.haml` (cap text), `app/controllers/report_controller.rb` (`deduction_cap_query` helper method, used in `max_score` view and `max_score_table`)
- Test: `test/integration/contests_controller_test.rb`, `test/integration/report_contest_scope_test.rb`

**Interfaces:**
- Produces: `ReportController#deduction_cap_query -> Hash` (`{}` when contest-scoped or no valid cap, else `{deduction_cap: n}`), a `helper_method`.

- [ ] **Step 1: tests.** Admin updates contest_a with cap 30 / limit 150 → saved; cap 120 → not saved, form shows the error; clone copies both; show page lists "30 points per problem" and "site setting (100)" when the limit is blank; Best Score page without a contest has `input[name=deduction_cap]`, with a contest has none and the scope card says "deduction cap 30" (or "no deduction cap"); `max_score_table` with `deduction_cap=30` puts `deduction_cap=30` in the table's data URL, with `abc` does not.
- [ ] **Step 2–4: fail, implement, pass.** Field copy: label "Deduction cap (points per problem)", hint "The most hints and AI help together can take off one problem's full score. Blank = no cap."; label "AI help spending limit (points per problem)", hint "The most points of AI help a student can spend on one problem before more requests are refused (hints are not counted). Blank = the site setting (currently N)." `extra_hint` (global page only): "Deduction cap: the most hints and AI help together take off one problem; blank = no cap. This page charges only the AI help used on each student's best-scoring submission, so a capped total here can differ from a contest's own report."
- [ ] **CHANGELOG** `### Added` bullet for the whole feature (extended in Task 5).

### Task 4: Student problem list

**Files:**
- Modify: `app/controllers/main_controller.rb` (`prepare_list_information`: use `HelpDeduction.losses`; set `@deduction_caps`, `@cap_notice_ids`), `app/views/main/_problem.html.haml`
- Create: `app/helpers/help_deduction_helper.rb`
- Test: `test/integration/main_list_deduction_test.rb`

**Interfaces:**
- Consumes: `running_contests_by_problem`, `cap_for`, `caps_disagree?`, `capped_problem_ids`, `losses`, `deduction`
- Produces: `HelpDeductionHelper#help_reduction_text(counted, raw, cap, notice) -> String|nil` — nil when `counted` is 0; "Full score reduced by N (capped; R before the cap)" when `cap && raw > cap`; "Full score reduced by N (contest grading may cap this)" when `notice`; else "Full score reduced by N". Numbers via `number_with_precision(x, precision: 2, strip_insignificant_zeros: true)`.

- [ ] **Step 1: tests** (contest mode unless said): one running contest, cap 30, AI 45 → "Full score reduced by 30 (capped; 45 before the cap)"; cap 30, AI 20 → "Full score reduced by 20"; two running contests, different problems, caps 30/20 → each problem its own; same problem in both with caps 30 and 20 → uncapped + "(contest grading may cap this)"; a hint revealed before the contest start does not count, one inside does ("1.5"); normal mode, problem in a capped contest of the student → notice; normal mode, no capped contest → plain; contest mode with no running contest → page renders, no "reduced".
- [ ] **Step 2–4: fail, implement, pass.** `@cap_notice_ids`: contest mode = problems whose running contests disagree; normal mode = `capped_problem_ids`. The view's score bar uses `[100, deduction].min`.

### Task 5: Spending limit and confirm boxes

**Files:**
- Modify: `app/models/submission.rb` (`llm_assist_refusal`), `app/helpers/help_deduction_helper.rb` (`help_budget_text`), `app/views/problems/_acquire_hint_confirm.html.haml`, `app/views/problems/_hints.html.haml` (pass the budget), `app/views/comments/_acquire_llm_assist_confirm.html.haml`, `app/views/submissions/_add_assist.html.haml` (pass the budget), `doc/Assist-History.md`, `CHANGELOG.md`
- Test: `test/models/submission_test.rb`, `test/helpers/help_deduction_helper_test.rb`

**Interfaces:**
- Consumes: `ai_spent`, `running_contests_by_problem`, `spending_limit_for`, `budget`
- Produces: `HelpDeductionHelper#help_budget_text(budget, cost:, kind:) -> String` (markdown; `kind` `:hint` or `:ai`; `''` for `:ai` when `cost` is 0)

- [ ] **Step 1: tests.** Refusal: site 100, spent 100 → "already spent 100 of the 100 points of AI help allowed on this problem"; contest limit 150, spent 100 → nil; contest limit 50, spent 60 → refused "of the 50"; two running contests limits 50 and nil (site 100) → 100 applies; normal mode with site 150 → spent 120 allowed; limit 0 → "no AI help is allowed on this problem". Helper: cap 30, lost 25 (hints 10, AI 15), hint cost 10 → three lines incl. "This hint costs 10, but only 5 more counts (25 → 30)."; lost 30 → "You have reached the cap, so this costs you nothing more."; no cap → only "Lost on this problem so far: 25 (hints 10, AI help 15)."; `:ai` adds "AI help on this problem stops once you have spent 150 points; you have spent 100."; `:ai` with cost 0 → "".
- [ ] **Step 2–4: fail, implement, pass.** Wording exactly as the spec's "Confirm boxes" section; the line "Contest NAME caps hint and AI deductions at N points per problem." comes first when a cap applies.
- [ ] **Docs:** `doc/Assist-History.md` entry (Problem observed: a student stopped at the fixed 100; Change: site setting + contest field; Outcome: pending deploy). CHANGELOG `### Added` bullet extended with the spending limit and the confirm-box text.

### Final: whole-branch check

- [ ] `bin/rails check` green; screenshots of the contest form, Best Score box, student list and both confirm boxes (throwaway system test, `HEADLESS=1`); one fresh reviewer over `hg diff`.
