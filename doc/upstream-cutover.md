# Upstream cutover — operational notes

Status snapshot of the long-deferred merge of this fork's `master`
(modern Rails 8 development line) into the world-facing upstream
[`cafe-grader-team/cafe-grader-web`](https://github.com/cafe-grader-team/cafe-grader-web),
which has been frozen on Rails 4.2 + Bootstrap 3 since October 2019.

Detailed strategy (retroactive multi-tag scheme, hg-git constraints,
deferred TODOs) lives in the memory file
`feedback_v2_upstream_cutover.md` and is not duplicated here.

**Last verified: 2026-05-20.**

## Where the cutover currently stands

- **Public notice**: [`cafe-grader-team#44`](https://github.com/cafe-grader-team/cafe-grader-web/issues/44)
  — open. Posted 2026-05-04. Notice window per the body ran through
  ~2026-05-19; window has elapsed.
- **Cutover PR**: [`cafe-grader-team#45`](https://github.com/cafe-grader-team/cafe-grader-web/pulls/45)
  — open, not merged. Source is `nattee/cafe-grader-web:master`,
  so it auto-tracks every push to the fork (the 4.3.3 release work
  flowed into it without manual intervention).
- **Tags on `cafe-grader-team/cafe-grader-web`**: only `v1.0.0`
  (= the frozen 2019 state, pre-cutover snapshot) is pushed upstream
  so far. `v2.0.0`, `v3.0.0`, `v4.0.0`, `v4.3.2`, and `4.3.3` exist
  locally and on `nattee/cafe-grader-web` but **not** on the upstream
  org repo.

## What happens AFTER PR #45 is merged

Order matters; do these in sequence.

### 1. Push the retroactive + recent tags to upstream

The cutover commit becomes the new `master` HEAD on
`cafe-grader-team/cafe-grader-web`. The retroactive tags should follow
so the historical version trail is visible on the upstream's
Tags/Releases pages.

```bash
# Add upstream as an hg path (not currently in .hg/hgrc)
# Append to [paths] in .hg/hgrc:
#   upstream = git+ssh://git@github.com/cafe-grader-team/cafe-grader-web

# Then push tags. hg push sends commits + tags together.
hg push upstream
```

Tags that should land upstream:

| Tag | Rev | Era |
|---|---|---|
| `v1.0.0` | 777 | already there |
| `v2.0.0` | 814 | Rails 5.2 era |
| `v3.0.0` | 901 | Rails 7 + Hotwire + BS5 era |
| `v4.0.0` | 1325 | Rails 8 + Solid Queue + LLM era |
| `v4.3.2` | 1564 | previous point release |
| `4.3.3` | 1718 | latest point release (added 2026-05-19) |

### 2. Tag and announce the cutover release

Per the original plan: don't reuse `v4.3.3` as the cutover marker —
that's a point release of the development line. Cut a fresh
**`v4.4.0`** to denote "this is what landed at upstream":

```bash
hg update master
hg tag v4.4.0
hg push upstream
hg push          # also sync the new tag to nattee/cafe-grader-web
```

Then on the upstream GitHub repo:
- Visit **Releases → Draft a new release → choose tag `v4.4.0`**.
- Title: e.g. "v4.4.0 — Rails 8 cutover".
- Body: the most recent CHANGELOG entry, plus a one-liner pointing at
  `MIGRATION.md` for the long-form context.

### 3. Sync chula_cp forward

Whichever the tag-bookkeeping commit lands on master, also merge it
forward to chula_cp so the deployment branch carries the same tag in
its history.

```bash
hg update chula_cp
hg merge master
hg commit -m 'merge master: tag v4.4.0 (upstream cutover)'
hg push          # tag now on the fork; we already pushed upstream above
```

### 4. Optional polish (deferred TODOs from memory)

These were noted in the upstream-cutover memory but never built. They
are nice-to-haves; the cutover doesn't depend on them.

1. **Release-bump rake task** — `bin/rails release:bump[X.Y.Z]` that
   writes `APP_VERSION`, commits, tags, and pushes in one step.
2. **Version display partial** showing `v#{APP_VERSION}#{APP_VERSION_SUFFIX}`
   in the footer / admin area so the running app's version is visible
   to deployers. Could include a deploy-time SHA from a `REVISION`
   file.

## What I cannot do from this session

- Merging PR #45 needs `gh auth login` (interactive) or `GH_TOKEN` set.
  It's a one-click merge in the GitHub web UI either way.
- Pushing to `cafe-grader-team/cafe-grader-web` needs that path added
  to `.hg/hgrc` first (see step 1).

## Pointers to related context

- **Memory `project_v2_upstream_cutover.md`** — strategy, retroactive
  multi-tag rationale, hg-git constraints, default-branch chronology
  table, deferred TODOs.
- **`CHANGELOG.md`** at repo root — `[4.3.3]` entry is the natural body
  for the upstream release notes.
- **`MIGRATION.md`** at repo root — the migration guide referenced in
  issue #44 and the PR body.
- **`doc/backlog.md`** — design-backlog tracker; nothing
  cutover-specific lives there.
