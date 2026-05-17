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
