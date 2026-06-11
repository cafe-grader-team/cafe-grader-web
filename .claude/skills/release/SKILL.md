---
name: release
description: Cut a cafe-grader release — version bump decision, CHANGELOG authoring, sliced commits, hg tag, chula_cp merge, push, GitHub release. Use when the user says "cut a release", "bump the version", "release X.Y.Z", or "prepare a release".
---

# Release pipeline (cafe-grader/web)

First used for v4.4.0 (2026-06-11). Two kinds of steps: **editorial** (judgment —
bump level, changelog prose) and **mechanical** (exact commands). Do not skip the
editorial ones; they are why this is a skill and not a rake task.

## Repo conventions (load-bearing)

- Version lives in the `APP_VERSION` file (read by `config/initializers/version.rb`,
  shown in the footer). `APP_VERSION_SUFFIX` must end up **empty** for a release.
- Tags are **v-prefixed** (`v4.3.2`, `v4.4.0`). The unprefixed `4.3.3` tag was a
  slip — do not repeat it.
- VCS is **hg with hg-git**; remote `default = git+ssh://git@github.com/nattee/cafe-grader-web`.
  GitHub-side objects (releases) are made with `gh -R nattee/cafe-grader-web`.
- Branch workflow: commits land on the **master bookmark**; `chula_cp` only ever
  receives batch-merges from master ("merge master: …" commits). Never commit
  directly on chula_cp.
- Commit style: `prefix: summary` first line, explanatory body, and end with
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- CHANGELOG.md is Keep-a-Changelog: `[Unreleased]` accumulates; cutting a release
  renames it to `[X.Y.Z] — YYYY-MM-DD` and opens a fresh empty `[Unreleased]`.

## Pipeline

### 1. Preflight (mechanical)

```bash
hg summary            # parent should carry the *master bookmark
hg status             # only expected work; .claude/settings.local.json stays uncommitted
bin/rails check       # minitest + rspec + swagger freshness — must be green
bundle exec rubocop <changed files>
bundle exec brakeman -q   # no NEW warnings in touched files
```

### 2. Decide the bump (editorial)

Semver against the last tag: additive features/endpoints → MINOR; fixes only →
PATCH; breaking contract changes → MAJOR. Call out behavioral changes that are
*arguably* breaking (e.g. the 4.4.0 token-TTL reduction) explicitly in the
changelog instead of silently bumping past them.

### 3. Author the CHANGELOG entry (editorial)

```bash
hg log -r "tag(<last-tag>)::." --template "{rev} {desc|firstline}\n"
```

The entry must describe the **whole tag-to-tag delta**, not just the current
session: if `[Unreleased]` is empty but commits landed since the last tag,
backfill them from the log. Group under `### Added / Changed / Fixed / Security`,
bold-led bullets, match the voice of previous entries. Cite rev numbers for
backfilled items.

### 4. Bump (mechanical)

```bash
echo "X.Y.Z" > APP_VERSION
: > APP_VERSION_SUFFIX        # must be empty on a release
```

No test pins the version string (verified for 4.4.0; re-grep if paranoid).

### 5. Commit work in logical slices (editorial slicing, mechanical commits)

Slice by subsystem with `hg commit <files> -m ...`. Note `hg commit` with an
explicit file list cannot split hunks within a file — files like `routes.rb`
go wholly into the first commit that needs them, with a body note.

### 6. Release commit + tag (mechanical)

```bash
hg commit APP_VERSION CHANGELOG.md -m "release: X.Y.Z ..."
hg tag vX.Y.Z          # v-prefix! creates its own commit; tag points at the release commit
```

### 7. Batch-merge into chula_cp (mechanical, message editorial)

```bash
hg update chula_cp
hg merge master        # resolve conflicts if chula-specific files overlap
hg commit -m "merge master: <topic summary>"   # body: "Batch of N (revA-revB): ..."
hg update master       # leave the working dir on master
```

### 8. Push (mechanical)

```bash
hg push                # hg-git converts the hg tag to a git tag
```

Verify both bookmark refs moved (`default/master`, `default/chula_cp` in `hg tags`
output, or push output). hg-git constraints: never rewrite pushed history; don't
lose `.hg/git-mapfile`.

### 9. GitHub release (mechanical)

GitHub never reads CHANGELOG.md — a Release is a separate object on top of the
tag, created **after** the push:

```bash
awk '/^## \[X.Y.Z\]/{f=1; next} /^## \[/{f=0} f' CHANGELOG.md > /tmp/notes.md
gh release create vX.Y.Z -R nattee/cafe-grader-web --title "vX.Y.Z" --notes-file /tmp/notes.md
```

### 10. Post-release

- Verify the release page renders.
- If the upstream-cutover memory/plan is affected (tag scheme, version timeline),
  update it.
