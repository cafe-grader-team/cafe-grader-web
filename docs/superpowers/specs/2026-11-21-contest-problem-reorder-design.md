# Contest problem reorder — fix and drag-and-drop (design, 2026-11-21)

Approved by dae 2026-11-21 (short design; small change).

## Problem

On a contest's Problems tab, pressing the up arrow on the bottom problem can
jump it two or more rows. Reproduced on the dev DB (rolled back):

| Action | Numbers after | Effect |
|---|---|---|
| empty contest, add A–D at once, up on D | A1 B2 D3 C4 | correct |
| contest already holds E, add A–D at once | E1 **A1** B2 C3 D4 | duplicate |
| then up on D (bottom row) | E1 A2 D3 B4 C5 | D jumps two rows |
| down on A from A1 B2 C3 D4 | B1 **A2 C2** D4 | duplicate + gap |
| cloned contest (numbers blank), up on D | D1 A2 B3 C4 | D jumps to top |

Three defects, one fragile mechanism:

1. `Contest#add_problems_and_assign_number` starts numbering at the current
   maximum instead of maximum + 1, so the first added problem repeats the last
   existing number.
2. `Contest#set_problem_number` moves a problem to `number ± 1.2` and shifts
   the others. It opens the gap at `ceil(target)` but places the problem at
   `round(target)`; for a move down (+1.2) those differ, giving a duplicate and
   a gap. The arithmetic also assumes numbers are exactly 1..n, so any repeat
   or gap makes a single press jump several rows.
3. `ContestsController#clone` copies contest problems without `number`.

## Goals

- One press of an arrow moves a problem exactly one row in the order shown.
- Drag-and-drop on the Problems tab sets the order directly.
- Every reorder leaves numbers 1..n with no repeats, healing old contests that
  already have repeats or blanks on their first reorder.
- One audit row per user action (existing `move_up` / `move_down`, new
  `reorder_problems`).

Non-goals: groups (their problems have no order), the student-facing list
code (it already orders by `contests_problems.number`), a data migration for
existing contests (the first reorder renumbers them).

## Approaches considered

1. **Patch the ±1.2 arithmetic** (use `round` for the gap). Fixes defect 2
   only; repeats from defects 1 and 3 still make one press jump. Rejected.
2. **Renumber the whole list on every move (chosen).** "Display order" is
   `number, id` (blank numbers first, as MySQL sorts NULL). A move swaps the
   problem with its neighbour in that order, then writes 1..n. Drag-and-drop
   sends the full new order and the same routine writes 1..n.
3. **Fractional/gapped numbering** (insert between neighbours). Saves writes,
   but contests hold ~10 problems, so writes are not a concern; rejected as
   more complex for no gain.

## Design

- Model (`Contest`): `problems_in_display_order`, `reorder_problems!(ids)`
  (writes 1..n in the given order; ids not in the contest ignored, contest
  problems missing from the list appended in their current order),
  `move_problem(problem, :up | :down)` (neighbour swap, then
  `reorder_problems!`). `add_problems_and_assign_number` starts at
  maximum + 1. `set_problem_number` is removed (no other caller).
- Clone copies `number` (the other per-problem settings stay as clone treats
  them today, to keep the change minimal).
- Controller: `do_problem` moveup/movedown call `move_problem`; new member
  action `POST reorder_problems` (param `problem_order`, comma-separated
  problem ids) behind the same filters as `do_problem` (editor, not
  finalized). `show_problems_query` orders by `number, id` and adds a
  `position` (1..n in display order) to each row.
- UI: the DataTables build already bundles RowReorder 1.5. The problem table
  orders by the hidden `position` column, gets a visible drag-handle column
  (`drag_indicator`), and `rowReorder: {dataSrc: 'position', selector:
  'td.reorder-handle', update: false}`. On `row-reorder` the table dispatches
  a bubbling `problems-reordered` DOM event with the new id order; the
  `contest` Stimulus controller fills a hidden form and submits it
  (Flavor B). The response is the usual toast + `datatable:reload`.
- Arrows stay, as "swap with the row next to it". Help text mentions both.
- Audit badge for `reorder_problems` in `AuditLogsHelper`.

## Left to the builder

Exact markup of the handle cell, toast wording, test file placement.
