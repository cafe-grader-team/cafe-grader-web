# Contest Problem Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One arrow press moves a contest problem exactly one row; drag-and-drop sets the order; numbers always end as 1..n.

**Architecture:** `Contest` gains a "display order" (`number, id`) and one routine that writes 1..n in a given order; arrows swap neighbours then call it, drag-and-drop posts the full order to a new member action. The problem DataTable uses the bundled RowReorder extension and a hidden Stimulus-driven form.

**Tech Stack:** Rails 8, Minitest, HAML, Stimulus, DataTables 2.3.4 + RowReorder 1.5.0 (already in `vendor/javascript/datatables/datatables.min.js`).

**Spec:** `docs/superpowers/specs/2026-11-21-contest-problem-reorder-design.md`

## Global Constraints

- VCS is **Mercurial**, not git. Commit with `hg commit <explicit files> -m …` only, and only when `[ "$(hg log -r . -T '{activebookmark}')" = "master" ]`; otherwise STOP. Never push.
- Commit message trailer: the one your harness gives you (a `Co-Authored-By` naming your own model is correct).
- Display order = `ORDER BY contests_problems.number, contests_problems.id` (MySQL puts NULL numbers first).
- Every reorder path writes numbers exactly 1..n; no fractional arithmetic remains.
- Audit: wrap row writes in `AuditLog.paused { … }`, then one `AuditLog.record!` per user action. Action strings: existing `move_up` / `move_down`; new `reorder_problems`.
- Mutating UI = hidden `form_with … data: {turbo: true}` + Stimulus (CLAUDE.md "Flavor B"); response = `@toast` + `@event_dispatcher` datatable reload + `render 'turbo_toast'`.
- `bin/rails test` must stay green before each commit.

## Review Focus

1. Legacy contest with repeated numbers (E1 A1 B2 C3 D4): up on the bottom row moves it exactly one row → pinned in Task 1 test `move_problem heals duplicates and moves one row`.
2. Legacy contest with all-blank numbers (cloned before this fix): up on the bottom row moves it one row, not to the top → Task 1 test `move_problem with blank numbers moves one row`.
3. Up on the top row / down on the bottom row: no change, numbers still 1..n → Task 1 test `move_problem at the edge is a no-op`.
4. `reorder_problems` posted with a foreign problem id, a duplicate id, or missing ids (stale page after someone else added a problem): foreign/duplicate ignored, missing ones appended in current order, never an exception → Task 1 test `reorder_problems! tolerates foreign, duplicate and missing ids`, Task 2 test `reorder_problems ignores ids outside the contest`.
5. A non-editor (normal user) posting `reorder_problems` is refused like `do_problem` → Task 2 test `normal user cannot reorder problems`.

---

### Task 1: Contest numbering model

**Files:**
- Modify: `app/models/contest.rb:96-125` (`add_problems_and_assign_number`, replace `set_problem_number`)
- Modify: `app/controllers/contests_controller.rb:149` (clone copies `number`) and `:371-386` (`do_problem` moveup/movedown)
- Test: `test/models/contest_test.rb`

**Interfaces:**
- Produces:
  - `Contest#problems_in_display_order -> Array<ContestProblem>` (ordered `number, id`)
  - `Contest#reorder_problems!(problem_ids) -> Array<Integer>` — accepts an Array of ids (Integers or Strings). Keeps ids that belong to the contest, first occurrence only, in the given order; appends contest problems not mentioned, in current display order; inside one `transaction` updates each row whose `number` differs from its 1-based index (`update!`). Returns the final problem-id order.
  - `Contest#move_problem(problem, direction) -> Integer | nil` — `direction` is `:up` or `:down`. Swaps with the neighbour in display order (no swap at the edge), then `reorder_problems!`. Returns the problem's new 1-based position; `nil` if the problem is not in the contest.
  - `set_problem_number` is deleted; its only caller, `ContestsController#do_problem`, is rewired in Step 2.

- [ ] **Step 1: Implement in `app/models/contest.rb`**

`add_problems_and_assign_number`: numbering starts at `(contests_problems.maximum(:number) || 0) + 1`. Add the three methods above; delete `set_problem_number`.

- [ ] **Step 2: Controller callers.** In `ContestsController#clone`, build each copy with `problem_id: cp.problem_id, number: cp.number`. In `do_problem`, moveup/movedown call `@contest.move_problem(@problem, :up | :down)` inside `AuditLog.paused` (drop the ±1.2 `delta`/`anchor` lines); `new_number` = the row's number afterwards; keep the existing `AuditLog.record!` shape and toast.

- [ ] **Step 3: Write the tests in `test/models/contest_test.rb`**

Use a helper in the test class:

```ruby
def numbers_of(contest)
  contest.problems_in_display_order.map { |cp| [cp.problem.name, cp.number] }
end
```

Tests (fixture `contest_a` holds `prob_add`=1, `easy`=2; `contest_c` is empty — add `hard` and other fixture problems as needed; set legacy numbers with `update_columns`):

- `add_problems_and_assign_number continues after the highest number` — on `contest_a`, add `hard` and save → `hard` has number 3.
- `move_problem heals duplicates and moves one row` — contest_c with four problems set to numbers `[1, 1, 2, 3]` plus a fifth at 4 (ids ascending in that order: build them in order); `move_problem(fifth, :up)` returns 4; display order has the fifth problem at index 3; numbers are `[1, 2, 3, 4, 5]`.
- `move_problem with blank numbers moves one row` — four problems all `number: nil`; `move_problem(last, :up)` returns 3; numbers are `1..4`; the formerly-third problem is now last.
- `move_problem down from the top does not duplicate` — 1..4; `move_problem(first, :down)` → order second, first, third, fourth; numbers `1..4`.
- `move_problem at the edge is a no-op` — `move_problem(first, :up)` returns 1 and order is unchanged; same for last with `:down`.
- `move_problem returns nil for a problem not in the contest`.
- `reorder_problems! tolerates foreign, duplicate and missing ids` — contest_c with A, B, C; call with `[C.id, problems(:some_other).id, C.id, A.id]` (as Strings for one of them) → returns `[C.id, A.id, B.id]`; numbers 1..3 in that order.

- [ ] **Step 4: Run** `bin/rails test test/models/contest_test.rb` → all pass.

- [ ] **Step 5: Commit**

```bash
hg commit app/models/contest.rb app/controllers/contests_controller.rb test/models/contest_test.rb -m "Contest problems: renumber 1..n on every move; add continues after the max; clone keeps numbers"
```

---

### Task 2: Controller, route, audit badge

**Files:**
- Modify: `app/controllers/contests_controller.rb` (filters at lines 2-27, `show_problems_query` ~line 234, new action after `do_problem`)
- Modify: `config/routes.rb:104` (contests member block, after `post 'do_problem'`)
- Modify: `app/helpers/audit_logs_helper.rb:55-58`
- Test: `test/integration/contests_controller_test.rb`

**Interfaces:**
- Consumes: `Contest#move_problem`, `#reorder_problems!`, `#problems_in_display_order` (Task 1).
- Produces: route helper `reorder_problems_contest_path(contest)` (POST, param `problem_order` = comma-separated problem ids); `show_problems_query` rows carry `position` (Integer, 1-based display order) in addition to today's keys, and the JSON array is in display order.

- [ ] **Step 1: New action `reorder_problems`**, listed in `set_contest`, `EDITOR_ACTION` and `check_finalized` exactly like `do_problem`. Parse `params[:problem_order].to_s.split(',')`. Record `before` = display-order problem ids, call `reorder_problems!` in `AuditLog.paused`; if the order changed, `AuditLog.record!(auditable: @contest, action: 'reorder_problems', object_changes: { 'order' => [before_names, after_names] })` with problem names. Toast title `"Contest #{@contest.name}"`, body `"The problem order was saved."`; reload `problem_table`.

- [ ] **Step 2: `show_problems_query`** orders by `'contests_problems.number', 'contests_problems.id'` and adds `position` (1..n).

- [ ] **Step 3: Audit badge** — `when 'reorder_problems'` → `bulk_badge 'swap_vert', 'reorder problems'`.

- [ ] **Step 4: Tests** in `test/integration/contests_controller_test.rb` (admin `sign_in_as("admin", "admin")`, `contest_a` = prob_add 1, easy 2; post `as: :turbo_stream`):
  - `moveup moves the bottom problem one row` — post `do_problem_contest_path(contest_a)` `problem_id: easy, command: 'moveup'` → `easy` number 1, `prob_add` number 2; one new `AuditLog` with action `move_up`.
  - `reorder_problems saves the posted order` — post `problem_order: "#{easy.id},#{prob_add.id}"` → numbers easy 1, prob_add 2; one `AuditLog` `reorder_problems`; response contains `"The problem order was saved."`.
  - `reorder_problems with the same order writes no audit row`.
  - `reorder_problems ignores ids outside the contest` — include `problems(:hard).id` → success, `hard` not added to contest_a.
  - `normal user cannot reorder problems` — `sign_in_as("john", "hello")` → numbers unchanged (assert redirect like the existing normal-user test).
  - `show_problems_query returns rows in display order with position` — after `update_columns` to give both number 1, JSON `data` ids follow `contests_problems.id` and `position` is `[1, 2]`.

- [ ] **Step 5: Run** `bin/rails test test/integration/contests_controller_test.rb test/models/contest_test.rb` → pass.

- [ ] **Step 6: Commit** `hg commit app/controllers/contests_controller.rb config/routes.rb app/helpers/audit_logs_helper.rb test/integration/contests_controller_test.rb -m "Contests: reorder_problems endpoint; arrows swap neighbours; problem query in display order"`

---

### Task 3: Drag-and-drop UI, help text, changelog

**Files:**
- Modify: `app/javascript/controllers/datatables/configs.js:159-213` (`contestManageProblem`)
- Modify: `app/javascript/controllers/contest_controller.js` (targets, new `postProblemOrder`)
- Modify: `app/views/contests/show.html.haml` (wrapper line 3 `data-action`, hidden form after line 20, help bullet ~line 289, table header ~line 298)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Fixed` and `### Added`)

**Interfaces:**
- Consumes: `reorder_problems_contest_path`, row key `position` (Task 2).
- Produces: DOM event `problems-reordered` (bubbles, `detail.order` = Array of problem ids in new order).

- [ ] **Step 1: DataTable config.** Column 0 becomes `{ data: 'position' }` (still hidden, still the `order: [[0, 'asc']]` column). Insert a new column at index 1: `{ data: null, className: 'reorder-handle text-muted', orderable: false, defaultContent: '<span class="mi" title="Drag to reorder" style="cursor: grab">drag_indicator</span>' }`. Shift `columnDefs` `orderable: false` targets to `[1, 2, 3, 4, 5, 6, 7]`. Add `rowReorder: { dataSrc: 'position', selector: 'td.reorder-handle', update: false }` and an `on: { 'row-reorder': handler }` entry (DataTables 2 init-time listeners). The handler computes the new order and dispatches the event:

```js
'row-reorder': function (e, diff) {
  if (!diff || diff.length === 0) return
  const api = $(e.target).DataTable()
  const moved = new Map(diff.map(d => [api.row(d.node).data().problem_id, d.newData]))
  const order = api.rows().data().toArray()
    .map(r => ({ id: r.problem_id, pos: moved.has(r.problem_id) ? moved.get(r.problem_id) : r.position }))
    .sort((a, b) => a.pos - b.pos)
    .map(r => r.id)
  e.target.dispatchEvent(new CustomEvent('problems-reordered', { bubbles: true, detail: { order } }))
}
```

- [ ] **Step 2: Stimulus + hidden form.** Add targets `problemOrderForm`, `problemOrderFormIds`; `postProblemOrder(event)` sets the ids field to `event.detail.order.join(',')` and `requestSubmit()`s. In `show.html.haml` add the hidden `form_with url: reorder_problems_contest_path, html: {'data-contest-target': 'problemOrderForm', data: {turbo: true}}` with `hidden_field :problem_order` (target `problemOrderFormIds`), and add `action: 'problems-reordered->contest#postProblemOrder'` to the `.contest-management-wrapper` data hash. Table header: add an empty `%th` (with `aria-label` "Drag to reorder") right after `%th Number`. Help bullet: "Drag a problem by its handle, or use the up/down arrows, to set the order students see."

- [ ] **Step 3: Browser check** (system-test recipe; `HEADLESS=1`). Write a throwaway test in the session scratchpad inheriting `ApplicationSystemTestCase`: admin logs in (`fill_in "Login"`/`"Password"`, `click_on "Login"`, `assert_current_path list_main_path, wait: 5`), opens `contest_path(contests(:contest_a))`, clicks the Problems tab, waits for both rows, drags the second row's `td.reorder-handle` onto the first row (`source.drag_to(target)`; if Selenium's HTML5 drag does not trigger RowReorder's mouse handlers, use `page.driver.browser.action.click_and_hold(src).move_to(dst, 0, -5).release.perform`), waits for `.toast` (`wait: 10`), then asserts `easy` has number 1. Also press the up arrow on the bottom row and assert one-row movement. Save a screenshot of the Problems tab to the scratchpad. Run `HEADLESS=1 bin/rails test <path>` → pass; report the screenshot path. Do not commit this file.

- [ ] **Step 4: CHANGELOG** under `[Unreleased]`: `### Fixed` — "Moving a contest problem up or down moves it exactly one row. Adding problems to a contest that already had some gave the first new one a repeated number, moving down created a repeat, and cloning dropped the order, so one press could jump two rows or to the top. Every move now renumbers the list 1..n, which also repairs older contests on their first move. (rev N)". `### Added` — "Drag-and-drop ordering on a contest's Problems tab (drag the handle at the left of each row). (rev N)". Use the rev of the Task 2 commit for both (`hg log -r . -T '{rev}'` before committing Task 3 gives the parent).

- [ ] **Step 5: Run** `bin/rails test` (full minitest) → green.

- [ ] **Step 6: Commit** `hg commit app/javascript/controllers/datatables/configs.js app/javascript/controllers/contest_controller.js app/views/contests/show.html.haml CHANGELOG.md -m "Contest problems: drag-and-drop ordering on the Problems tab"`
