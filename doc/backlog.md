# Backlog

Design refactors, deferred decisions, and "someday" follow-ups that don't yet
warrant a GitHub issue or fit in a single TODO comment. Each entry should be
short — title, why it matters, current state, proposed direction, rough size.
Trim or move to an issue when you start the work.

Conventions:
- One section per entry. Keep them grep-able.
- Cite file paths so the next reader (or Claude) can jump in cold.
- Don't put per-commit TODOs here — those go inline as `# TODO(scope): …`.
- Don't put scheduled or assigned work here — that goes on GitHub.

---

## Help patterns — follow-ups under the context-dependent split

**Decision (2026-05-17).** Two patterns coexist intentionally: inline
knowledge card (`_xxx_help.html.haml`) on index/overview pages where space
is available and visibility matters for new admins; offcanvas drawer on
edit/detail pages where space is at a premium. Convention written into
CLAUDE.md under "Frontend & UI Conventions". Do NOT unify onto a single
pattern; that earlier plan was rejected.

**Discoverability.** Offcanvas trigger buttons must be labeled (`? Help`),
not icon-only. Codified in CLAUDE.md. First-visit popover pointing at the
button is a future enhancement using the existing cookie-based
`dismiss-announcement` controller pattern — deferred until we see whether
the visible label alone is enough.

**Open items under this split.**
- **Orphan partial.** `app/views/contests/_contest_help.html.haml` is
  defined but rendered nowhere (no `render.*contest_help` hits). Either
  wire it into `contests/index.html.haml` (inline card pattern) or delete.
- **Shared offcanvas helper.** When a second view gets a help drawer,
  extract `app/views/shared/_help_drawer.html.haml` taking `id:`, `title:`,
  `body_partial:` locals so we don't copy-paste the offcanvas chrome. One
  drawer doesn't justify the partial yet; two do.
- **Edit-drawer content density.** `problems/_edit_help.html.haml` content
  is still text-heavy. The point of the drawer was to relieve a dense
  page; the help inside shouldn't reproduce that density. Consider tabs
  inside the drawer (Basics / Datasets / Viva / Tags) or a numbered
  walkthrough rather than field-by-field reference. Defer until we have
  a second drawer to compare against.

**Out of scope.** `app/views/main/help.html.haml` is a full-page
student-facing help with i18n — different concern, not covered by the
admin help-pattern split.

---

## `/problems/edit` icon polish

**Done (2026-05-17).** `finance` → `query_stats` everywhere
(`problems/edit`, `problems/index`, `report/problem_hof_view`,
`_edit_help` body text). Magic 480px → `.offcanvas-help` class in
`my_custom.scss`.

**Still pending.** Drawer content density rewrite — `_edit_help` is still
text-heavy. The point of the drawer was to relieve a dense page; the help
inside shouldn't reproduce that density. Consider tabs inside the drawer
(Basics / Datasets / Viva / Tags) or a numbered walkthrough rather than
field-by-field reference. Defer until a second drawer exists for comparison.

## Legacy tooltip attribute form

**Done (2026-05-17).** Rewrote ~13 occurrences across 8 views to flat
`data: {bs_toggle: …, bs_title: …}` form. Files touched:
`graders/index`, `report/problem_hof_view`, `report/problem_hof`,
`viva_sessions/show`, `problems/index` (×8), `problems/_ds_import`,
`datasets/_testcases`. Verified by grep — no `'bs-toggle'` /
`'bs-dismiss'` / `'bs-title'` string-key forms remain (excluding the
`graders/index.html.haml.orig` merge backup; that file is unrelated
to the convention sweep).

**Stale backup.** `app/views/graders/index.html.haml.orig` is a
Mercurial merge backup. Worth deleting if it's no longer needed.

---

## Dead partial: `contests/_contest_help`

**Why.** `app/views/contests/_contest_help.html.haml` exists but is rendered
nowhere (grep `render.*contest_help` → no hits). Either there's a forgotten
intent to surface it, or it should be deleted.

**Proposed direction.** Decide during help-pattern unification — if we keep
offcanvas drawers everywhere, this content might want to live in a
`contests/edit` drawer. If not, delete.

**Size.** Trivial. Roll into the unification pass.

---

## AuditLog destroy test

**Why.** The "Auditable must exist" bug (fixed 2026-05-17 by making
`belongs_to :auditable` optional) wasn't caught because there's no test
for the destroy path on any audited model. There's only an integration
test for the controller (`test/integration/audit_logs_controller_test.rb`),
not a model-level test that confirms an audit row is created on destroy.

**Proposed direction.** Add a model test like:
```ruby
test "destroying an audited record writes a destroy audit row" do
  c = contests(:something)
  assert_difference -> { AuditLog.for(c).where(action: 'destroy').count }, 1 do
    c.destroy!
  end
end
```
Cover at least one audited model per shape (own-row destroy + cascade via
`dependent: :destroy`).

**Size.** Small. ~30 min.

---

## System-test suite has 20 stale failures

**Why.** `bin/rails test:system` currently reports **12 failures + 8 errors** out of 30 tests on master tip (verified 2026-05-21). Most are tests that fell behind UI / model changes, NOT broken production behavior — but they need triaging case by case because some may have caught real regressions. None are caused by the 4.3.3 release work itself; they existed before and were noticed only after we wrote a new system test that ran cleanly through `bin/rails test:system`.

**Six root-cause clusters (not 20 independent bugs).** Tackle one cluster per session.

### Cluster 1 — Name-validation tightened, tests use spaces (~15 min)
Tests use names like `"Updated Group"`, `"GroupA"`, `"easybeginner"` that contain characters the new validation rejects:
> "Name contains invalid characters. Only letters, numbers, `( ) [ ] - _` are allowed."

Failing:
- `test/system/tags_test.rb#test_update_tag`
- `test/system/groups_test.rb#test_create_new_group`, `#test_update_group`
- `test/system/contests_test.rb#test_create_new_contest`, `#test_update_contest`

**Decision needed:** is the regex (no spaces) the desired behavior, or did it get tightened by accident? Either relax the validation OR update the test names. Probably the former — spaces in user-facing names are normal.

### Cluster 2 — `select2_select` helper now ambiguous (~15 min)
`test/system/problems_manage_test.rb:139` (`select2_select` helper) does `find('.select2-search__field')`. The problems-edit page now has 3 select2 fields (tags, groups, allowed languages), so the helper hits `Capybara::Ambiguous`.

Failing:
- `ProblemsManageTest#test_add_tags_to_problem`
- `ProblemsManageTest#test_set_permitted_languages`
- `ProblemsManageTest#test_add_problem_to_group`

**Fix:** scope the helper to take a `within:` block or a label argument so callers identify *which* select2 they mean.

### Cluster 3 — Problem available-toggle UI flow drift (~30-60 min)
The available/view_testcase toggle clicks succeed but the test's read-back doesn't show the new value.

Failing:
- `ProblemsManageTest#test_set_available_to_yes` / `#test_set_available_to_no`
- `ProblemsManageTest#test_select_all_then_apply_action`
- `ProblemsManageTest#test_apply_action_to_multiple_individually_selected_problems`

**Verify manually first:** does the toggle actually work in the browser? If yes, the test's wait/assertion needs an update (probably needs to wait for the turbo_stream update). If no, real regression — likely from our recent Pass B `link_to → button_to` migration or related polish.

### Cluster 4 — date_added handling regression (~30 min)
`ProblemsManageTest#test_change_date_added` raises `NoMethodError: undefined method 'to_date' for nil` at line 53. The test reads back the date_added; somewhere it's nil where it shouldn't be.

**Verify manually first**, same as cluster 3 — could be feature-broken or test-out-of-date.

### Cluster 5 — "Go" button gone (~15 min)
Submissions index has lost a `Go` button.

Failing:
- `SubmissionsTest#test_admin_view_submissions`
- `SubmissionsTest#test_user_view_submissions`

**Possible:** the per-row action was renamed to `View` or replaced with an icon-only button during recent polish. Update the test selector; confirm the user-visible name today is correct.

### Cluster 6 — Users-page UI drift (~60-90 min)
Multiple distinct UI changes; tests reference elements that have moved.

Failing:
- `UsersTest#test_add_new_user_and_edit` — email `a@a.com` no longer shown on the list page
- `UsersTest#test_add_multiple_users` — `remark1` not visible after bulk add (similar to above; columns differ?)
- `UsersTest#test_try_using_admin_from_normal_user` — `/main/list` returned where `/main/login` expected (auth flow differs)
- `UsersTest#test_grant_admin_right` — `Unable to find field "login"` (Admins-grant form changed)
- `UsersTest#test_login_then_change_password` — `Unable to find css 'button[type="submit"]'` on profile page

Each needs a quick look at the corresponding view to find the new selector. Possibly the Users admin index dropped some columns to make the table denser (good change; tests need updating).

### Recommended sequence

1. Clusters 1 + 2 first — clearly test-needs-update with low risk. Knock them out in one short session.
2. Cluster 5 — small, just need to know the new button name.
3. Cluster 6 — multiple small issues, but each is local.
4. Clusters 3 + 4 — bigger; verify the feature in a browser before touching tests, as these might be real regressions.

**`bin/rails test` (non-system) is clean** — only one pre-existing failure remains there (`ReportControllerTest#test_admin_can_access_cheat_report`, MySQL collation issue, separate concern).
