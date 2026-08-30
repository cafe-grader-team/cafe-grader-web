# Viva Grounding Materials — Design

**Date:** 2026-07-19
**Status:** Approved design, ready for implementation plan
**Area:** Viva exam authoring (`app/services/llm/viva_*`, `Problem`, `Tag`)

## Problem

Viva-exam problems attach **grounding material** — reference content (lecture
slides, model solutions, textbook excerpts, plus the occasional typed note) that
the LLM interviewer and grader treat as authoritative. Today this lives on the
`Tag` model as `kind: viva_grounding` (`app/models/tag.rb`), injected into the
LLM messages via `Problem#viva_grounding_tags` and `Tag#grounding_payload`
(`viva_turn_assist.rb:119`, `viva_grade_assist.rb:97`).

Two things are wrong with the current situation:

1. **Authoring is barely built.** The tag form only renders a content textarea
   `- if @tag.kind == 'llm_prompt'` (`tags/_form.html.haml:9`), so a
   `viva_grounding` tag has **no content field at all**, and `tag_params`
   (`tags_controller.rb:73`) does **not** permit `:files` — even though
   `Tag has_many_attached :files` and `grounding_payload` reads them. Grounding
   is effectively only populatable from the Rails console. Attachment to a
   problem is a single flat `select2` over `Tag.all` (`problems/_form.html.haml:47`)
   mixing labels, prompts, and grounding docs; there is no inline visibility of
   what a grounding tag contains.
2. **`Tag` is overloaded.** It serves four `kind`s: `normal`/`topic` (labels),
   `llm_prompt` (system-prompt instructions), `viva_grounding` (reference
   documents). The last is a *content asset*, not a label, and it will grow
   document-native behavior (see Requirements) that doesn't belong on a label
   table.

**Not the problem:** the *normalization* is correct. A grounding item is a
shared record joined many-to-many to problems (upload/write once, reference from
many). That stays.

## Requirements (from brainstorming)

- **Normalization preserved:** one grounding record, referenced by many problems.
- **Content is file-first, occasionally text, sometimes both:** uploaded PDFs/docs
  are primary; a typed markdown note is a secondary content source on the same item.
- **Token-budgeting is a firm requirement.** Grounding is re-sent on *every*
  interview turn — the typed `body` as text and each file as a base64 PDF `image_url`
  part — so a fat lecture deck quietly inflates per-turn cost. Authors need a
  per-item token estimate and a per-problem total. **Reuse-analysis** ("used by N
  problems") is part of this budgeting view.
- **Grounding is instructor-only inside the platform.** Student distribution of
  reference material happens through other channels (Discord / LMS / Google Doc),
  so grounding needs no `public` flag, color, or student-facing tag filter.
- **Not needed:** a searchable library; topic/course inheritance (grounding is
  attached per-problem, not inherited through a topic); per-attachment metadata.

## Decision

Extract grounding into a **dedicated `GroundingMaterial` model** with its own
small admin library and a viva-scoped attach control on the problem form.
`llm_prompt` **stays on `Tag`** (small, always text, and working); unifying it
into a shared "LLM asset" model is a deferred backlog item, not this work.

### Why not the alternatives

- **Finish the authoring UI on `Tag` (A+):** cheaper (no migration), and the
  attach idiom is shared either way. Rejected because the confirmed
  token-budgeting + reuse-analysis features are document-native — on `Tag` each
  becomes a `kind`-conditional branch and `kind`-filtered aggregation, growing
  the exact overload we want to shed. The `public`/color/student-filter machinery
  is also dead weight (and a leakage footgun) for an instructor-only content asset.
- **Unify `llm_prompt` + `viva_grounding` into one `LlmAsset` (C):** cleanest
  architecture, but rewrites the *working* rubric-injection path — regression
  risk beyond the pain this work addresses. Kept on the backlog.

## Correction (discovered during planning, 2026-07-19)

The original spec assumed uploaded grounding files were text-extracted into
`metadata['extracted_text']`. **They never were** — there is no PDF gem, analyzer,
or extraction job in the codebase; `Tag#grounding_payload` reads a key nothing
writes, so file grounding has always contributed empty text (only typed `params`
text ever reached the model). Decision: deliver grounding files to the LLM as
base64 `image_url` PDF parts, reusing the proven `pdf_attachment` mechanism
(`request.rb:125`) — the statement PDF already works exactly this way. This removes
the async-extraction machinery, preserves visual fidelity for slides, and adds no
dependency. Sections 1 and 3 reflect this; `estimated_tokens` and the payload
methods are defined accordingly.

## Design

### Section 1 — Data model

New table `grounding_materials`:

| column | type | purpose |
|---|---|---|
| `title` | string, not null | human label — "Dijkstra lecture notes" |
| `description` | text, null | instructor note: what this is / when to use it |
| `body` | mediumtext, null | typed markdown content (the "text" half) |
| `estimated_tokens` | integer, default 0 | **cached** token estimate for budgeting |
| timestamps | | |

- `has_many_attached :files` — PDF/image files only (validated on `content_type`,
  matching how `pdf_attachment` guards `application/pdf`). Delivered to the LLM as
  base64 `image_url` parts, **not** text-extracted (see "Correction" above).
- `grounding_text` — the typed `body` markdown wrapped under a `## Grounding
  Material` header; returns `nil` when `body` is blank. (Replaces the old
  `Tag#grounding_payload`, which folded in non-existent `extracted_text`.)
- `grounding_file_parts` — an array of `image_url` content-part hashes, one per
  attached PDF/image file, produced by the reusable `encode_pdf_part` helper
  (Section 3). Returns `[]` when no files are attached.
- `estimated_tokens` — cached; recomputed **after save** (attachments settled),
  written via `update_column` to avoid callback recursion: `body.length / 4` for
  the text plus a coarse **size-based proxy** per file (from `blob.byte_size`,
  labeled approximate — no page count without a PDF lib). Both inputs are known
  synchronously at save time, so the async-extraction recompute wrinkle is gone.
  Accurate page-count budgeting via `pdf-reader` is a deferred upgrade.
- **Association:** `has_and_belongs_to_many :problems` via a plain
  `grounding_materials_problems` join (mirrors `problems_tags`, no join model —
  no per-link data needed). `Problem` gets
  `has_and_belongs_to_many :grounding_materials`. Promote to `has_many :through`
  only if per-attachment metadata is ever needed (deferred).

`Tag` keeps `normal`, `topic`, `llm_prompt`. `viva_grounding` is retired from the
enum after backfill.

### Section 2 — UI

**A. Grounding library** — `GroundingMaterialsController`, admin-only, mirrors
`TagsController`; `resources :grounding_materials, except: [:show]`; linked from
the **Manage** navbar dropdown alongside Tags / Audit logs.

- **Index** doubles as the budgeting/reuse surface — a
  `.table.table-hover.table-condense.align-middle` (per the admin DataTables
  convention):

  | Title | Content | Est. tokens | Used by | actions |
  |---|---|---|---|---|
  | Dijkstra lecture notes | 2 files · text | ≈ 3,200 | 7 problems | ✎ 🗑 |

  "Est. tokens" and "Used by N problems" (`grounding_material.problems.count`,
  linking to the problem list) are the v1 token-budgeting + reuse-analysis — no
  separate screen. Actions column follows progressive condensation (icon-only for
  1–2 controls).
- **Form** (`_form`): `title`, short `description`, a `body` markdown textarea,
  and — the piece missing on `Tag` today — a **multi-file upload** with a list of
  attached files plus per-file remove/purge. Shows the item's current est. tokens.
- `new` / `edit` are thin wrappers around `_form`.

**B. Attach control on the problem form** — after migration `viva_grounding` is
gone from `Tag`, so the existing `tag_ids` select naturally shows only
labels + `llm_prompt`. Add a second `select2`:

```haml
= form.input :grounding_material_ids, collection: GroundingMaterial.all,
    input_html: {class: 'select2', multiple: true}
```

The problem form already carries a `viva-mode-toggle` Stimulus controller
(`problems/_form.html.haml:2`). Place the grounding select in a block that is
**shown only when `compilation_type == viva_exam`** — nothing else consumes
grounding. Directly under it, a **per-problem total**: "Attached grounding ≈
4,200 tokens — re-sent every turn," computed **server-side on render** (sum of
selected materials' `estimated_tokens`). A Stimulus live-update as the select
changes is optional polish, deferred.

**C. Inline visibility** — each attached material in the block shows
*title · ≈ tokens · a "view" link* to its edit page, resolving the round-trip
complaint. A fancy inline preview modal is deferred.

### Section 3 — Integration, migration, loose ends

**Reusable PDF encoder** — extract the base64 body of `pdf_attachment`
(`request.rb:125`) into `encode_pdf_part(attachment)` on `Llm::Request`, then have
`pdf_attachment` call it for `problem.statement`. Statement and grounding files
then share one encoder (and the same `application/pdf` guard).

**Turn assembly** (`viva_turn_assist.rb`):
- `grounding_block` (`:118`) sources text from
  `@problem.grounding_materials.filter_map(&:grounding_text)` instead of the tag
  payload.
- `build_first_user_content` (`:107`) appends
  `@problem.grounding_materials.flat_map(&:grounding_file_parts)` after the
  statement PDF part — grounding PDFs ride in the same first user message, re-sent
  each turn like the statement.

**Grade assembly** (`viva_grade_assist.rb`):
- Grounding **body text** stays in the system prompt (rubric context, as today),
  sourced from `grounding_text` (`:97`).
- Grounding **file parts** go in the grader's *user* message (system messages
  can't carry images), alongside the statement PDF.

**Problem model:** remove `viva_grounding_tags`; `has_and_belongs_to_many
:grounding_materials` replaces it. `viva_prompt_tags` (llm_prompt) stays.

**Migration & backfill** — three ordered, separately-committed steps, safe on
`chula_cp` where real grounding data may exist:

1. **Schema:** create `grounding_materials` + `grounding_materials_problems`.
2. **Data (idempotent):** for each `Tag` with `kind: viva_grounding` → create a
   `GroundingMaterial` (`title`←`name`, `description`←`description`,
   `body`←`params`), **attach the same blobs** (`gm.files.attach(tag.files.blobs)`
   — non-destructive; original tag attachment left intact), copy its `problems`,
   recompute `estimated_tokens`.
3. **Cleanup:** destroy migrated `viva_grounding` tags + their `ProblemTag`
   links, then drop `viva_grounding` from the `Tag` enum. Steps 2–3 stay in
   separate migrations so a mid-flight failure can't half-delete before the copy
   is verified.

**Docs & changelog** (all currently reference "viva_grounding tags"):

- `doc/Viva-Exam.md` — §3, the wire-shape diagrams, the authoring checklist.
- `problems/_form.html.haml` compilation-type helper text,
  `problems/_edit_help.html.haml`, `problems/edit.html.haml`,
  `config/locales/en.yml`.
- `CHANGELOG.md` `[Unreleased]`: **Added** grounding materials + library;
  **Changed** grounding moved off tags.
- `doc/backlog.md`: add the "someday — unify `llm_prompt` into an `LlmAsset`"
  note (deferred alternative C).

**Verify during implementation:** the `course-viva-prep` skill authors viva kits
— if it programmatically creates `viva_grounding` tags, switch it to
`GroundingMaterial`. Checklist item so it doesn't silently break.

**Testing** (written after the feature, per standing preference): `grounding_text`
/ `grounding_file_parts` and `estimated_tokens` computed from `body` + file sizes;
`encode_pdf_part` shared by statement and grounding; turn + grade assembly include
grounding text and image parts; library CRUD + file upload; the viva-scoped attach
+ per-problem token total; a backfill spot-check. `GroundingMaterial` is **not**
audited (matches `Tag`, which is not in the `audited` set).

## Out of scope / deferred

- Searchable grounding library.
- Topic/course inheritance of grounding.
- Live (JS) per-problem token total; inline preview modal.
- Accurate page-count token estimate for files (`pdf-reader`); v1 uses a size-based proxy.
- Per-attachment metadata (`has_many :through` upgrade).
- Unifying `llm_prompt` into a shared LLM-asset model (backlog).
