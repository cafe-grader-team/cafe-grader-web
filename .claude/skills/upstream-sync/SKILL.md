---
name: upstream-sync
description: Push the fork's modern master line out to the world-facing upstream cafe-grader-team/cafe-grader-web — merge the tracking PR, propagate tags, cut the cutover release. Use when the user says "do the upstream cutover", "sync upstream", "push to cafe-grader-team", or "land master upstream".
---

# Upstream sync / cutover pipeline (cafe-grader/web)

First exercised **2026-06-13** (the Rails 4.2 → Rails 8 cutover, 773 commits).
Pushes the fork's modern `master` line out to the world-facing upstream. Two kinds
of steps: **editorial** (judgment — which tags, marker name, release prose) and
**mechanical** (exact commands). Don't skip the editorial ones.

## The two repos (do not conflate)

- **`nattee/cafe-grader-web`** — the fork; primary development; the **only** remote
  `hg push` talks to (`hg paths` → `default`). Mirrored from the local hg repo via
  hg-git.
- **`cafe-grader-team/cafe-grader-web`** — the world-facing upstream the user also
  owns; frozen on Rails 4.2 + Bootstrap 3 since Oct 2019 until the cutover. It is
  **not** an hg path and receives nothing automatically.

The cutover travels through a long-lived **tracking PR** (`nattee:master` →
upstream `master`) that **auto-follows every push to the fork** — so it is always
current and needs no branch prep.

## Load-bearing rules (dangerous to get wrong)

1. **Tags reach upstream via the GitHub API, NEVER `hg push upstream`.** A raw
   hg-git push to a fresh remote tries to export *every* local head — leaking
   private branches (`chula_cp`, `dae`, `toi-contest`, `codejom`, `java-bm`,
   `algo-bm`…) into the public repo. The API method creates exactly the refs you
   name and touches nothing else.
2. **Merge the PR with a MERGE COMMIT (`--merge`), never squash/rebase.** Squash
   collapses hundreds of commits into one (history gone); rebase rewrites every
   SHA, orphaning the `.hg/git-mapfile`. Merge-commit preserves both.
3. **`gh` does the whole thing headlessly** — merge, tag refs, releases, issue
   close. (An older doc claimed merging needed interactive auth; it does not.)
4. **The marker tag points at the MERGE COMMIT and lives on upstream only** — keep
   cutover-specific tags out of the fork's `.hgtags`.
5. **Tags' target commits must already exist upstream.** The PR merge brings the
   tagged commits into upstream history, so create the tag refs *after* the merge.

## Pipeline

### 1. Preflight (mechanical)

```bash
gh auth status                                   # logged in; scope includes 'repo'
UP=cafe-grader-team/cafe-grader-web; FORK=nattee/cafe-grader-web; PR=<n>
gh pr view $PR -R $UP --json mergeable,mergeStateStatus   # want MERGEABLE / CLEAN
gh api repos/$UP/branches/master/protection 2>&1         # 404 = no protection
```
`mergeable: UNKNOWN` means GitHub hasn't computed it yet — re-poll. The fork's
master descends from the frozen upstream master, so a clean merge is expected.

### 2. Decide (editorial)

- **Which tags** go upstream — epoch tags + recent point releases. Skip known slips
  (e.g. the unprefixed `4.3.3`) to keep the public repo clean.
- **Marker tag name** (e.g. `rails8-cutover`); it points at the *merge commit*.
- **Merge-commit message** — subject names the leap; body points at `MIGRATION.md`
  and closes the notice issue.

### 3. Merge the tracking PR (mechanical — IRREVERSIBLE, world-facing)

Get explicit user sign-off first; this publishes the whole diff.

```bash
gh pr merge $PR -R $UP --merge \
  --subject "Merge #$PR: <leap summary>" \
  --body "<what landed; see MIGRATION.md; closes #<notice>>"
MERGE_SHA=$(gh api repos/$UP/commits/master --jq '.sha')   # capture for the marker
```

### 4. Propagate tags via the GitHub API (mechanical)

```bash
for tag in v2.0.0 v3.0.0 v4.0.0 v4.3.2 v4.4.0 v4.4.1; do   # adjust the list
  sha=$(gh api repos/$FORK/commits/$tag --jq '.sha')        # resolve on the fork
  gh api repos/$UP/git/refs -X POST -f ref="refs/tags/$tag" -f sha="$sha"
done
gh api repos/$UP/git/refs -X POST -f ref="refs/tags/rails8-cutover" -f sha="$MERGE_SHA"
```
`gh api .../commits/<tag>` dereferences a tag to its commit SHA regardless of
lightweight/annotated. A ref that already exists (e.g. `v1.0.0`) returns 422 —
harmless; skip it.

### 5. Headline Release + close the notice (mechanical, prose editorial)

```bash
gh release create rails8-cutover -R $UP --title "<headline>" \
  --notes-file notes.md --latest
gh issue comment <notice> -R $UP --body "Cutover complete … see release + MIGRATION.md"
gh issue close <notice> -R $UP
```
Write **bespoke** release notes for a big cutover — one point-release CHANGELOG
entry won't represent the span. Point at `MIGRATION.md`; sketch the version trail.

### 6. Verify (mechanical)

```bash
gh pr view $PR -R $UP --json state          # MERGED
gh api repos/$UP/tags --jq '.[].name'       # all intended tags present
gh release view -R $UP --json tagName       # headline release exists
```

## What this pipeline does NOT touch

- The local hg repo / `.hgtags` (the marker lives only upstream).
- The fork `nattee/cafe-grader-web` (already current; the PR tracked it).
- Any private branch — by construction (API tags + PR merge only).

## Related context

- `doc/upstream-cutover.md` — the historical record of the first cutover.
- Memory `project_v2_upstream_cutover.md` — strategy, retroactive tag scheme.
- `/release` skill — the sibling pipeline for cutting fork point releases.
- `MIGRATION.md`, `CHANGELOG.md` — sources for release-note prose.
