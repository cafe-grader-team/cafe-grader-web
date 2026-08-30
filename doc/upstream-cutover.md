# Upstream cutover — record + procedure

The long-deferred merge of this fork's modern `master` (Rails 8 development line)
into the world-facing upstream
[`cafe-grader-team/cafe-grader-web`](https://github.com/cafe-grader-team/cafe-grader-web)
— frozen on Rails 4.2 + Bootstrap 3 since October 2019.

## Status: DONE (2026-06-13)

The cutover completed on 2026-06-13. Upstream `master` now carries the full modern
line (773 commits: Rails 8, Solid Queue, Hotwire, JSON API, LLM assist, audit
logging, new judge engine).

- **Merge**: PR
  [`cafe-grader-team#45`](https://github.com/cafe-grader-team/cafe-grader-web/pull/45)
  merged with a **merge commit** (`e42bbcba`). PR shows *Merged*.
- **Tags upstream**: `v1.0.0` (pre-existing frozen marker) + `v2.0.0`, `v3.0.0`,
  `v4.0.0`, `v4.3.2`, `v4.4.0`, `v4.4.1`, created via the **GitHub API** (not
  `hg push`). The unprefixed `4.3.3` slip was deliberately **not** propagated.
- **Marker**: `rails8-cutover` tag points at the merge commit; it lives **only**
  on upstream (kept out of the fork's `.hgtags`).
- **Release**: headline
  [`rails8-cutover`](https://github.com/cafe-grader-team/cafe-grader-web/releases/tag/rails8-cutover)
  Release, marked Latest, body points at `MIGRATION.md`.
- **Notice**: issue
  [`cafe-grader-team#44`](https://github.com/cafe-grader-team/cafe-grader-web/issues/44)
  commented (window elapsed) and closed.

## How it was done — and the procedure for next time

The repeatable procedure is the **`/upstream-sync` skill**
(`.claude/skills/upstream-sync/SKILL.md`). Use it for any future fork→upstream
sync. The load-bearing decisions captured there:

1. **Tags via the GitHub API, never `hg push upstream`.** A raw hg-git push to a
   fresh remote would try to export every local head and leak private branches
   (`chula_cp`, `dae`, `toi-contest`, …) into the public repo. The API method
   creates exactly the refs named and nothing else.
2. **Merge-commit, never squash/rebase.** Squash destroys history; rebase rewrites
   SHAs and orphans the hg-git mapfile.
3. **`gh` does the whole thing headlessly** — merge, tags, release, issue close.
   (An earlier version of this doc wrongly said merging needed interactive auth.)
4. The tracking PR auto-follows `nattee:master`, so it is always current.

## Version-trail tag scheme (retroactive epochs)

| Tag | Era |
|---|---|
| `v1.0.0` | Rails 4.2 + Bootstrap 3 (the frozen 2019 upstream state) |
| `v2.0.0` | Rails 5.2 era |
| `v3.0.0` | Rails 7 + importmap + Hotwire + Bootstrap 5 |
| `v4.0.0` | Rails 8 + Solid Queue + LLM era |
| `v4.3.2` / `v4.4.0` / `v4.4.1` | point releases on the modern line |
| `rails8-cutover` | the cutover merge commit (upstream-only marker) |

## Pointers to related context

- **`.claude/skills/upstream-sync/SKILL.md`** — the reusable pipeline.
- **Memory `project_v2_upstream_cutover.md`** — strategy, retroactive-tag
  rationale, hg-git constraints, default-branch chronology.
- **`MIGRATION.md`** (repo root) — the migration guide linked from the cutover
  release and the (now closed) notice issue.
- **`/release` skill** — sibling pipeline for cutting fork point releases.
