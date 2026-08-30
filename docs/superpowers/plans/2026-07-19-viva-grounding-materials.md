# Viva Grounding Materials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move viva grounding material off the overloaded `Tag` model into a dedicated `GroundingMaterial` model with a real authoring UI, token-budget surface, and viva-scoped attach control — delivering grounding files to the LLM as base64 `image_url` PDF parts.

**Architecture:** A new `GroundingMaterial` model (title, description, body markdown, cached `estimated_tokens`, `has_many_attached :files`) joined many-to-many to `Problem`. Grounding *text* (`body`) rides in the LLM messages as a text part; grounding *files* ride as base64 `image_url` parts via a class-method encoder shared with the existing statement-PDF path. `llm_prompt` stays on `Tag`. Existing `viva_grounding` tags are backfilled, then that `Tag` kind is retired.

**Tech Stack:** Ruby 3.4.4 / Rails 8.0 (`load_defaults 7.0`), MySQL 8 (`utf8mb4_0900_ai_ci`), HAML + simple_form + Bootstrap 5, ActiveStorage, Hotwire/Turbo, Minitest. VCS is Mercurial (`hg`).

## Global Constraints

- **All commits land on `master`.** Before any `hg commit`, run `hg log -r . --template '{activebookmark}\n'`; if it prints `chula_cp`, run `hg update master` first. Never commit on `chula_cp`.
- **`hg commit` names explicit files** — never a bare `hg commit` (repos carry unrelated dirty changes). New files must be `hg add`ed first.
- **MySQL only, `utf8mb4_0900_ai_ci` collation** on every new table (`test/schema_collation_test.rb` enforces it). Rails' MySQL adapter applies it from `config/database.yml`; do not override per-column.
- **Testing is tests-after, not TDD** (engineer's standing preference): implementation tasks 1–7 each end with a concrete manual/console verification; automated Minitest coverage is consolidated in Task 8 with full test code. This deliberately deviates from the writing-plans TDD default.
- **Data attributes use flat keys** in HAML/tag helpers (`data: { bs_toggle: 'tooltip' }`), never nested hashes.
- **Server-mutating clicks use a `<form>`** with `form: {data: {turbo: true}}`, never `link_to ..., remote: true` (Turbo link-driving is disabled globally).
- **Icons** use the `.mi` class (`%span.mi edit`), not raw SVG or `material-icons`.
- **CHANGELOG** `[Unreleased]` gets a curated bullet in the *same commit* as any user/operator-facing change, citing the rev.

---

### Task 1: Schema, `GroundingMaterial` model, and `Problem` association

Additive only — nothing existing is removed, so the app and current viva flow keep working.

**Files:**
- Create: `db/migrate/<ts>_create_grounding_materials.rb`
- Create: `app/models/grounding_material.rb`
- Modify: `app/models/problem.rb` (add association near the other `has_many`/attachment declarations, ~line 156)

**Interfaces:**
- Produces: `GroundingMaterial` with `#grounding_text -> String|nil`, `#grounding_file_parts -> Array<Hash>`, `#estimated_tokens -> Integer` (cached), `#compute_estimated_tokens -> Integer`; `has_and_belongs_to_many :problems`; `Problem#grounding_materials`.
- Note: `grounding_file_parts` calls `Llm::Request.encode_pdf_part`, which lands in Task 2. Task 1's console verification (Step 5) does not invoke `grounding_file_parts`, so the method being undefined until Task 2 is harmless — do not reorder these two tasks.

- [ ] **Step 1: Generate the migration file**

Run: `bin/rails generate migration CreateGroundingMaterials`
Then replace its contents with:

```ruby
class CreateGroundingMaterials < ActiveRecord::Migration[8.0]
  def change
    create_table :grounding_materials do |t|
      t.string  :title, null: false
      t.text    :description
      t.text    :body, size: :medium
      t.integer :estimated_tokens, null: false, default: 0
      t.timestamps
    end

    create_join_table :grounding_materials, :problems do |t|
      t.index [:grounding_material_id, :problem_id],
              unique: true, name: 'idx_gm_problems_unique'
      t.index :problem_id
    end
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: creates `grounding_materials` and `grounding_materials_problems`; `db/schema.rb` updated with both tables at `utf8mb4_0900_ai_ci`.

- [ ] **Step 3: Write the model**

Create `app/models/grounding_material.rb`:

```ruby
class GroundingMaterial < ApplicationRecord
  # PDF/image files delivered to the LLM as base64 image_url parts (see
  # Llm::Request.encode_pdf_part). No text extraction — matches the statement PDF.
  ALLOWED_CONTENT_TYPES = %w[application/pdf image/png image/jpeg image/webp].freeze

  # Coarse token proxy for a binary PDF/image sent as an image_url part:
  # ~1 page ≈ 100 KB ≈ 258 tokens on Gemini, so ~1 token per 400 bytes.
  # Deliberately approximate; a pdf-reader page count is a deferred upgrade.
  BYTES_PER_PROXY_TOKEN = 400

  has_and_belongs_to_many :problems
  has_many_attached :files

  validates :title, presence: true
  validate :files_are_pdf_or_image

  after_commit :recompute_estimated_tokens

  # Text contribution to the LLM message: the typed body under a heading the
  # model can recognize. nil when there is no typed text.
  def grounding_text
    return nil if body.blank?
    "## Grounding Material\n\n#{body}"
  end

  # One image_url content-part per attached PDF/image, using the shared encoder.
  def grounding_file_parts
    files.filter_map { |f| Llm::Request.encode_pdf_part(f) }
  end

  def compute_estimated_tokens
    text_tokens = (body.to_s.length / 4.0).ceil
    file_tokens = files.sum { |f| (f.byte_size.to_f / BYTES_PER_PROXY_TOKEN).round }
    text_tokens + file_tokens
  end

  private

  # update_column bypasses callbacks, so this after_commit does not re-fire.
  def recompute_estimated_tokens
    fresh = compute_estimated_tokens
    update_column(:estimated_tokens, fresh) if fresh != estimated_tokens
  end

  def files_are_pdf_or_image
    files.each do |f|
      next if ALLOWED_CONTENT_TYPES.include?(f.content_type)
      errors.add(:files, "#{f.filename} must be a PDF or image (got #{f.content_type})")
    end
  end
end
```

- [ ] **Step 4: Add the `Problem` association**

In `app/models/problem.rb`, directly after the `has_one_attached`/`has_many_attached` block (near line 158), add:

```ruby
  has_and_belongs_to_many :grounding_materials
```

Do **not** remove `viva_grounding_tags` yet — the services still use it until Task 3.

- [ ] **Step 5: Verify in console**

Run:
```bash
bin/rails runner '
  gm = GroundingMaterial.create!(title: "Dijkstra notes", body: "Shortest paths.\n" * 40)
  puts gm.grounding_text[0, 30]
  puts "estimated_tokens=#{gm.reload.estimated_tokens}"
  puts "problems assoc responds: #{Problem.new.respond_to?(:grounding_materials)}"
  gm.destroy
'
```
Expected: prints the heading, a non-zero `estimated_tokens` (~body length / 4), and `problems assoc responds: true`. No errors.

- [ ] **Step 6: Commit**

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add app/models/grounding_material.rb db/migrate/*_create_grounding_materials.rb
hg commit app/models/grounding_material.rb app/models/problem.rb db/migrate/*_create_grounding_materials.rb db/schema.rb \
  -m "Add GroundingMaterial model + problem association

Dedicated home for viva grounding (title, body, files, cached
estimated_tokens), joined many-to-many to Problem. Additive; the
viva_grounding Tag path still works until the service cutover.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Shared `encode_pdf_part` class-method encoder

Refactor the statement-PDF base64 logic into a stateless class method both the statement path and grounding files use. Behavior-preserving for the statement.

**Files:**
- Modify: `app/services/llm/request.rb:120-140` (the `pdf_attachment` method)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Llm::Request.encode_pdf_part(attachment) -> {type: "image_url", image_url: String} | nil` (nil for a non-`application/pdf` or unattached attachment). Instance `#pdf_attachment` now delegates to it. `GroundingMaterial#grounding_file_parts` (Task 1) consumes it.

- [ ] **Step 1: Add the class method and delegate**

In `app/services/llm/request.rb`, replace the `pdf_attachment` method (lines ~120-140) with:

```ruby
    # Base64-encode a single attachment as an OpenAI-compatible image_url
    # content part. Returns nil when the attachment is absent or not a PDF —
    # callers treat that as "no part for this source." Stateless class method
    # so both the instance statement path and GroundingMaterial can share it.
    def self.encode_pdf_part(attachment)
      return nil unless attachment&.attached?
      return nil unless attachment.content_type == 'application/pdf'

      encoded = Base64.strict_encode64(attachment.download)
      {
        type:      "image_url",  # API spec uses 'image_url' for this content type
        image_url: "data:application/pdf;base64,#{encoded}"
      }
    rescue => e
      msg = "Failed to build PDF attachment (#{attachment&.filename}): #{e.message}"
      Rails.logger.error msg
      raise RuntimeError, msg
    end

    # The problem statement PDF as an image_url part (or nil). Used by
    # CommentAssist and the viva subclasses.
    def pdf_attachment
      self.class.encode_pdf_part(problem&.statement)
    end
```

Note: `encode_pdf_part` only accepts `application/pdf` (matching the old guard). Grounding image files (png/jpeg/webp) pass the model validation but are **not** sent as parts in v1 — only PDFs reach the model. This is acceptable: grounding is overwhelmingly PDF; document image support is a trivial later extension (add their content types + a `data:<type>;base64,` branch here). Flag this in Task 7 docs.

- [ ] **Step 2: Verify the statement path is unchanged**

Run: `bin/rails runner '
  p = Problem.joins(:statement_attachment).first rescue nil
  puts p ? "has statement: #{p.statement.content_type}" : "no problem with statement in dev DB (ok)"
  puts Llm::Request.respond_to?(:encode_pdf_part)
'`
Expected: prints `true` for the method; statement line prints either the content type or the "no problem" note. No errors.

- [ ] **Step 3: Verify grounding file parts encode**

Run: `bin/rails runner '
  gm = GroundingMaterial.create!(title: "t")
  file = Rack::Test::UploadedFile.new(Rails.root.join("public/404.html"), "application/pdf") rescue nil
  puts "encoder returns nil for non-pdf-less: #{Llm::Request.encode_pdf_part(gm.files.first).inspect}"
  gm.destroy
'`
Expected: prints `nil` (no files attached) — confirms nil-safety. No errors.

- [ ] **Step 4: Commit**

```bash
hg commit app/services/llm/request.rb \
  -m "Extract encode_pdf_part class method for reuse

Statement PDF and grounding files now share one stateless base64
image_url encoder. Statement behavior unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Service cutover — turn + grade assembly read `grounding_materials`

Swap both viva services from `viva_grounding` tags to `grounding_materials`, delivering `body` as text and files as image_url parts. Then remove `Problem#viva_grounding_tags`.

**Files:**
- Modify: `app/services/llm/viva_turn_assist.rb:107-122`
- Modify: `app/services/llm/viva_grade_assist.rb:37-56, 93-99`
- Modify: `app/models/problem.rb:163-165` (remove `viva_grounding_tags`)

**Interfaces:**
- Consumes: `Problem#grounding_materials` (Task 1), `GroundingMaterial#grounding_text`, `#grounding_file_parts` (Task 1/2).
- Produces: no new public interface; the LLM payloads now carry grounding from materials.

- [ ] **Step 1: Turn assist — text source + file parts**

In `app/services/llm/viva_turn_assist.rb`, change `build_first_user_content` (line ~107) and `grounding_block` (line ~118) to:

```ruby
    def build_first_user_content
      parts = [{type: 'text', text: scenario_message}]
      grounding = grounding_block
      parts << {type: 'text', text: grounding} if grounding
      pdf = pdf_attachment
      parts << pdf if pdf
      parts.concat(grounding_file_parts)
      parts.length == 1 ? scenario_message : parts
    end

    # Concatenated grounding body text, with a markdown header. nil when none.
    def grounding_block
      texts = @problem.grounding_materials.filter_map(&:grounding_text)
      return nil if texts.empty?
      texts.join("\n\n---\n\n")
    end

    # image_url parts for every attached grounding file across all materials.
    def grounding_file_parts
      @problem.grounding_materials.flat_map(&:grounding_file_parts)
    end
```

Note: `grounding_text` already includes the `## Grounding Material` header per material; joining multiple with `---` keeps them separable. (The old single-header behavior is close enough; if a single combined header is preferred, drop the header from `grounding_text` and add it here — not required for v1.)

- [ ] **Step 2: Grade assist — body text in system prompt, files in user message**

In `app/services/llm/viva_grade_assist.rb`, change `build_scenario_content` (line ~52) and `assemble_context` (line ~93):

```ruby
    def build_scenario_content
      parts = [{type: 'text', text: scenario_message}]
      pdf = pdf_attachment
      parts << pdf if pdf
      parts.concat(@problem.grounding_materials.flat_map(&:grounding_file_parts))
      parts.length == 1 ? scenario_message : parts
    end

    def assemble_context
      prompt = @problem.viva_prompt_tags.map(&:params).reject(&:blank?).join("\n\n")
      raise RuntimeError, "There is no llm_prompt tag attached to problem '#{@problem.name}' — viva needs a prompt tag" if prompt.blank?

      grounding = @problem.grounding_materials.filter_map(&:grounding_text).join("\n\n---\n\n")
      [prompt, grounding].reject(&:blank?).join("\n\n")
    end
```

- [ ] **Step 3: Remove `Problem#viva_grounding_tags`**

In `app/models/problem.rb`, delete the method (lines ~163-165):

```ruby
  def viva_grounding_tags
    tags.where(kind: :viva_grounding)
  end
```

Leave `viva_prompt_tags` intact.

- [ ] **Step 4: Verify no remaining references + payload preview builds**

Run:
```bash
grep -rn "viva_grounding_tags\|grounding_payload" app --include="*.rb"    # expect: no output
bin/rails runner '
  s = Submission.joins(:problem).where(problems: {compilation_type: Problem.compilation_types[:viva_exam]}).last rescue nil
  puts s ? "viva submission ##{s.id} present; preview would build" : "no viva submission in dev DB (ok)"
'
```
Expected: the grep prints nothing; the runner prints one of the two notes. No `NoMethodError`.

- [ ] **Step 5: Commit**

```bash
hg commit app/services/llm/viva_turn_assist.rb app/services/llm/viva_grade_assist.rb app/models/problem.rb \
  -m "Viva services read grounding from GroundingMaterial

Turn + grade assembly now source grounding body text and image_url
file parts from problem.grounding_materials; removed viva_grounding_tags.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Grounding library (routes, controller, views, navbar)

Admin CRUD for grounding materials, with the index doubling as the token-budget + reuse surface. Mirrors `TagsController`/`AnnouncementsController` patterns.

**Files:**
- Modify: `config/routes.rb:54` (add resource block after `resources :tags`)
- Create: `app/controllers/grounding_materials_controller.rb`
- Create: `app/views/grounding_materials/index.html.haml`
- Create: `app/views/grounding_materials/new.html.haml`
- Create: `app/views/grounding_materials/edit.html.haml`
- Create: `app/views/grounding_materials/_form.html.haml`
- Modify: `app/views/layouts/_header.html.haml:58` (add nav link after Tags)

**Interfaces:**
- Consumes: `GroundingMaterial` (Task 1).
- Produces: routes `grounding_materials_path`, `new/edit_grounding_material_path`, `delete_file_grounding_material_path(gm)`.

- [ ] **Step 1: Routes**

In `config/routes.rb`, after the `resources :tags ... end` block (line ~57), add:

```ruby
  resources :grounding_materials, except: [:show] do
    delete 'delete_file', on: :member
  end
```

- [ ] **Step 2: Controller**

Create `app/controllers/grounding_materials_controller.rb`:

```ruby
class GroundingMaterialsController < ApplicationController
  before_action :admin_authorization
  before_action :set_grounding_material, only: %i[edit update destroy delete_file]

  def index
    @grounding_materials = GroundingMaterial.order(:title)
  end

  def new
    @grounding_material = GroundingMaterial.new
  end

  def edit; end

  def create
    @grounding_material = GroundingMaterial.new(gm_params)
    attach_files(@grounding_material)
    if @grounding_material.save
      redirect_to grounding_materials_path, notice: 'Grounding material created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @grounding_material.assign_attributes(gm_params)
    attach_files(@grounding_material)
    if @grounding_material.save
      redirect_to grounding_materials_path, notice: 'Grounding material updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @grounding_material.destroy
    redirect_to grounding_materials_path, notice: 'Grounding material deleted.'
  end

  # DELETE /grounding_materials/:id/delete_file?blob_id=NN
  def delete_file
    blob = @grounding_material.files.find_by(id: params[:blob_id])
    blob&.purge
    redirect_to edit_grounding_material_path(@grounding_material), notice: 'File removed.'
  end

  private

  def set_grounding_material
    @grounding_material = GroundingMaterial.find(params[:id])
  end

  # Append newly uploaded files (never replace); per-file removal is delete_file.
  def attach_files(gm)
    uploads = Array(params.dig(:grounding_material, :files)).reject(&:blank?)
    gm.files.attach(uploads) if uploads.any?
  end

  def gm_params
    params.require(:grounding_material).permit(:title, :description, :body)
  end
end
```

Note: `files` are handled by `attach_files` (append semantics), not through `gm_params`, so re-editing a material doesn't wipe existing files.

- [ ] **Step 3: `_form` partial**

Create `app/views/grounding_materials/_form.html.haml`:

```haml
= simple_form_for @grounding_material, html: { id: 'edit_form' }, wrapper: :horizontal_form do |f|
  = render 'application/error_for_model', model: @grounding_material
  = f.input :title
  = f.input :description, input_html: { rows: 2 }, hint: 'Internal note: what this is / when to use it.'
  = f.input :body, label: 'Grounding text (markdown)', input_html: { rows: 12 },
      hint: 'Typed reference material. Files below are sent to the model as PDFs.'

  .mb-3
    %label.form-label Files (PDF)
    = f.input :files, as: :file, label: false, input_html: { multiple: true }, wrapper: :horizontal_file
    - if @grounding_material.files.attached?
      .mt-2
        - @grounding_material.files.each do |file|
          .card.bg-light.border-0.mb-1
            .card-body.p-2.d-flex.align-items-center.justify-content-between
              = link_to "#{content_tag(:span, 'description', class: 'mi md-18')} #{file.filename}".html_safe, url_for(file), class: 'text-decoration-none text-truncate'
              = button_to delete_file_grounding_material_path(@grounding_material, blob_id: file.id),
                  method: :delete, class: 'btn btn-sm btn-link text-danger p-0', form: { class: 'd-inline', data: { turbo: true, turbo_confirm: 'Remove this file?' } } do
                %span.mi.md-18 delete

  .d-flex.gap-2
    = f.button :submit, 'Save', class: 'btn btn-primary'
    = link_to 'Cancel', grounding_materials_path, class: 'btn btn-outline-secondary'
```

- [ ] **Step 4: `index`, `new`, `edit` views**

Create `app/views/grounding_materials/index.html.haml`:

```haml
.d-flex.justify-content-between.align-items-center.mb-4
  %h3.mb-0 Grounding Materials
  = link_to new_grounding_material_path, class: 'btn btn-primary d-inline-flex align-items-center gap-1' do
    %span.mi add
    Add grounding

%table.table.table-hover.table-condense.align-middle
  %thead
    %tr
      %th Title
      %th Content
      %th.text-end Est. tokens
      %th.text-end Used by
      %th
  %tbody
    - @grounding_materials.each do |gm|
      %tr
        %td= gm.title
        %td.text-secondary
          - bits = []
          - bits << "#{gm.files.count} file#{'s' if gm.files.count != 1}" if gm.files.attached?
          - bits << 'text' if gm.body.present?
          = bits.join(' · ').presence || '—'
        %td.text-end{ title: 'Approximate — body chars/4 + file size proxy' }= "≈ #{number_with_delimiter(gm.estimated_tokens)}"
        %td.text-end= pluralize(gm.problems.count, 'problem')
        %td.align-middle.py-1.pr-2
          .d-flex.gap-1.justify-content-end
            = link_to edit_grounding_material_path(gm), class: 'btn btn-outline-secondary border-0 py-1 px-2', title: 'Edit' do
              %span.mi edit
            = button_to grounding_material_path(gm), method: :delete, class: 'btn btn-outline-danger border-0 py-1 px-2', title: 'Delete', form: { class: 'd-inline', data: { turbo: true, turbo_confirm: "Delete '#{gm.title}'?" } } do
              %span.mi delete
- if @grounding_materials.empty?
  %p.text-secondary.mt-3 No grounding materials yet.
```

Create `app/views/grounding_materials/new.html.haml`:

```haml
%h3.mb-4 New Grounding Material
= render 'form'
```

Create `app/views/grounding_materials/edit.html.haml`:

```haml
%h3.mb-4 Edit Grounding Material
= render 'form'
```

- [ ] **Step 5: Navbar link**

In `app/views/layouts/_header.html.haml`, after the `Tags` line (line ~58), add:

```haml
                %li= link_to 'Grounding', grounding_materials_path, class: 'dropdown-item'+active_class_when(controller: :grounding_materials)
```

- [ ] **Step 6: Verify the library end-to-end (manual)**

Run `bin/dev`, log in as admin, open **Manage → Grounding**. Create a material with a title, some body text, and a PDF upload. Expected: it appears in the index with a non-zero "Est. tokens" (body + file proxy), "0 problems", the "1 file · text" content summary; Edit shows the attached file with a working Remove button.

- [ ] **Step 7: Commit**

```bash
hg add app/controllers/grounding_materials_controller.rb app/views/grounding_materials
hg commit config/routes.rb app/controllers/grounding_materials_controller.rb app/views/grounding_materials app/views/layouts/_header.html.haml \
  -m "Add grounding materials library UI

Admin CRUD under Manage → Grounding; index shows est. tokens and reuse
count; multi-file PDF upload with per-file removal.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

(The CHANGELOG bullet is authored in Task 7 Step 3 — deliberately batched with the other docs so the user-facing entry lands once the whole feature is in place.)

---

### Task 5: Problem form — viva-scoped grounding attach + per-problem token total

Add a grounding `select2` shown only in viva mode, with a server-side token total.

**Files:**
- Modify: `app/javascript/controllers/viva_mode_toggle_controller.js` (add an inverse `showForViva` target)
- Modify: `app/views/problems/_form.html.haml` (add grounding block after the tags input, ~line 47)
- Modify: `app/controllers/problems_controller.rb:456` (permit `grounding_material_ids`)

**Interfaces:**
- Consumes: `Problem#grounding_materials`, `GroundingMaterial#estimated_tokens`.
- Produces: `problem[grounding_material_ids][]` params saved on the problem.

The existing `viva-mode-toggle` controller (scope = the `turbo_frame_tag :problem` wrapping the form) only has a `hideForViva` target that *hides* fields when `compilation_type == viva_exam`. Grounding needs the inverse — *show only for viva* — so we add a `showForViva` target.

- [ ] **Step 1: Add the inverse `showForViva` target to the controller**

In `app/javascript/controllers/viva_mode_toggle_controller.js`, change the `static targets` line and add one line inside `toggle()` (leave the imports, comments, and class declaration unchanged):

```javascript
  static targets = ["hideForViva", "showForViva"]

  connect() {
    this.toggle()
  }

  toggle() {
    const checked = this.element.querySelector('input[name$="[compilation_type]"]:checked')
    const value   = checked?.value
    this.hideForVivaTargets.forEach(el => el.classList.toggle("d-none", value === "viva_exam"))
    this.showForVivaTargets.forEach(el => el.classList.toggle("d-none", value !== "viva_exam"))

    this.dispatch("compilation-type-changed", { detail: { value }, prefix: "mode" })
  }
```

- [ ] **Step 2: Add the grounding block to the problem form**

In `app/views/problems/_form.html.haml`, after the tags input (line ~47, inside the `turbo_frame_tag :problem` scope the controller manages), add. It starts with `d-none` so it stays hidden until `connect()` reveals it for viva problems (no flash for non-viva):

```haml
        -# Viva grounding — shown only when compilation_type is viva_exam
        .mb-4.d-none{ data: { viva_mode_toggle_target: 'showForViva' } }
          = form.input :grounding_material_ids, label: 'Grounding materials',
              collection: GroundingMaterial.order(:title), value_method: :id, label_method: :title,
              input_html: { class: 'select2', multiple: true, id: 'problem_grounding_material_ids' },
              wrapper: :horizontal_form,
              hint: 'Reference material the interviewer/grader treat as authoritative. Re-sent every turn.'
          - attached = @problem.grounding_materials.to_a
          - if attached.any?
            .form-text.text-secondary
              Attached grounding ≈ #{number_with_delimiter(attached.sum(&:estimated_tokens))} tokens — re-sent every turn.
              %ul.mb-0
                - attached.each do |gm|
                  %li
                    = gm.title
                    %span.text-secondary= "· ≈ #{number_with_delimiter(gm.estimated_tokens)} tokens ·"
                    = link_to 'view', edit_grounding_material_path(gm)
```

Note on `id:` — the explicit `id: 'problem_grounding_material_ids'` prevents Select2 duplicate-id breakage.

- [ ] **Step 3: Permit the param**

In `app/controllers/problems_controller.rb`, in the `problem_params` `permit(...)` (line ~456), add `grounding_material_ids: []` alongside `tag_ids: []`:

```ruby
                                      :view_submission, tag_ids: [], group_ids: [], grounding_material_ids: [])
```

- [ ] **Step 4: Verify (manual)**

Restart `bin/dev`. Edit a **non-viva** problem: the grounding select is hidden. Switch compilation type to **Viva Exam**: the grounding select appears. Attach a grounding material, save, reopen: it's selected and the "Attached grounding ≈ N tokens" line lists it with a working "view" link. Edit a normal problem type and confirm the grounding block stays hidden.

- [ ] **Step 5: Commit**

```bash
hg commit app/javascript/controllers/viva_mode_toggle_controller.js app/views/problems/_form.html.haml app/controllers/problems_controller.rb \
  -m "Attach grounding materials on viva problems

Viva-only select2 (new showForViva toggle target) + server-side
per-problem token total on the problem form; grounding_material_ids permitted.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Backfill existing `viva_grounding` tags, then retire the kind

Migrate any real `viva_grounding` tags into `GroundingMaterial` (non-destructive copy first, cleanup second), then drop the enum value.

**Files:**
- Create: `db/migrate/<ts>_backfill_grounding_materials_from_tags.rb`
- Create: `db/migrate/<ts>_remove_viva_grounding_tags.rb`
- Modify: `app/models/tag.rb:4` (drop `viva_grounding` from the enum)

**Interfaces:**
- Consumes: `GroundingMaterial`, `Tag` with `kind: viva_grounding`.
- Produces: populated `grounding_materials` + join rows.

- [ ] **Step 1: Backfill migration (idempotent, non-destructive)**

Create `db/migrate/<ts>_backfill_grounding_materials_from_tags.rb`:

```ruby
class BackfillGroundingMaterialsFromTags < ActiveRecord::Migration[8.0]
  # Copy viva_grounding tags → GroundingMaterial. Non-destructive: original
  # tags and their attachments stay until the next migration.
  def up
    viva_grounding_kind = 3 # Tag.kinds[:viva_grounding] at time of writing
    Tag.where(kind: viva_grounding_kind).find_each do |tag|
      next if GroundingMaterial.exists?(title: tag.name) # idempotent guard
      gm = GroundingMaterial.create!(
        title:       tag.name,
        description: tag.description,
        body:        tag.params
      )
      tag.files.blobs.each { |blob| gm.files.attach(blob) } # share blobs, non-destructive
      gm.problems << tag.problems.to_a
      gm.reload.send(:recompute_estimated_tokens)
    end
  end

  def down
    # Best-effort: remove materials that mirror a still-present viva_grounding tag.
    GroundingMaterial.where(title: Tag.where(kind: 3).pluck(:name)).destroy_all
  end
end
```

Note: references `Tag`/`GroundingMaterial` models directly (acceptable for a one-shot data migration on this codebase). If the enum has already been edited when this runs in a fresh setup, the literal `3` still matches historical rows.

- [ ] **Step 2: Cleanup migration**

Create `db/migrate/<ts>_remove_viva_grounding_tags.rb`:

```ruby
class RemoveVivaGroundingTags < ActiveRecord::Migration[8.0]
  def up
    # ProblemTag join rows + attachments purge via destroy callbacks.
    Tag.where(kind: 3).find_each(&:destroy)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- [ ] **Step 3: Run the migrations and verify the data moved**

Run:
```bash
bin/rails db:migrate
bin/rails runner '
  puts "remaining viva_grounding tags: #{Tag.where(kind: 3).count}"   # expect 0
  puts "grounding materials: #{GroundingMaterial.count}"
'
```
Expected: 0 remaining `viva_grounding` tags; `GroundingMaterial.count` reflects however many existed (0 in a fresh dev DB — the backfill is a no-op there, which is fine). The migrations run while `Tag` **still has** the `viva_grounding` enum value and `has_many_attached :files`, so the backfill's `tag.files`/`tag.params` reads work. Retiring them happens next, after the data has moved.

- [ ] **Step 4: Retire the enum value (only now that no viva_grounding rows remain)**

In `app/models/tag.rb`, line 4, change:

```ruby
  enum :kind, {normal: 0, topic: 1, llm_prompt: 2, viva_grounding: 3}
```
to:
```ruby
  enum :kind, {normal: 0, topic: 1, llm_prompt: 2}
```

Remove the now-dead `grounding_payload` method (`tag.rb:10-15`). Remove `has_many_attached :files` from `Tag` **only if** nothing else uses tag files — verify with `grep -rn "\.files" app --include="*.rb" | grep -i tag` (expect no non-grounding hits); if unsure, leave it (harmless).

- [ ] **Step 5: Verify no live viva_grounding references remain**

Run: `grep -rn "viva_grounding" app config --include="*.rb" --include="*.haml" --include="*.yml"`
Expected: only UI copy / locale strings remain (fixed in Task 7) — no enum use, no `Tag.kinds` reference.

- [ ] **Step 6: Commit**

```bash
hg add db/migrate/*_backfill_grounding_materials_from_tags.rb db/migrate/*_remove_viva_grounding_tags.rb
hg commit db/migrate/*_backfill_grounding_materials_from_tags.rb db/migrate/*_remove_viva_grounding_tags.rb app/models/tag.rb db/schema.rb \
  -m "Backfill grounding materials from tags; retire viva_grounding kind

Copy then remove viva_grounding tags; drop the enum value and dead
grounding_payload from Tag.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**Production sequencing note:** run the backfill migration *before* the Task 3 service code is live on a data-bearing deployment (chula_cp), so grounding is never briefly lost. In a single deploy that ships all migrations + code together this is automatic (migrations run first).

---

### Task 7: Docs, changelog, backlog, and the course-viva-prep skill

Update every place that says "viva_grounding tags" and record the change.

**Files:**
- Modify: `doc/Viva-Exam.md` (§3, wire diagrams, checklist, decision log)
- Modify: `app/views/problems/_form.html.haml:61` (compilation-type helper text)
- Modify: `app/views/problems/_edit_help.html.haml:36`, `app/views/problems/edit.html.haml:48`
- Modify: `config/locales/en.yml:169`
- Modify: `CHANGELOG.md` (`[Unreleased]`)
- Modify: `doc/backlog.md`
- Check: the `course-viva-prep` skill files

- [ ] **Step 1: Fix in-app copy**

In `app/views/problems/_form.html.haml:61`, change the Viva Exam option text `attach llm_prompt + viva_grounding tags instead` → `attach an llm_prompt tag + grounding materials instead`.
In `app/views/problems/_edit_help.html.haml` and `app/views/problems/edit.html.haml`, replace the `%code viva_grounding` references with prose pointing to **Manage → Grounding** and the problem form's grounding select.
In `config/locales/en.yml`, remove the `viva_grounding: Viva Exam Grounding` line under the tag kinds (line ~169).

- [ ] **Step 2: Rewrite `doc/Viva-Exam.md` §3 and diagrams**

Replace §3 "`viva_grounding` tags" with a "Grounding materials" section: they are `GroundingMaterial` records (Manage → Grounding), attached per-problem via the viva-only select; `body` text is injected as a `## Grounding Material` text part and each file as a base64 `image_url` PDF part (re-sent every turn, like the statement). Update the two wire-shape code blocks to show grounding file parts in the user message (turn) and the grader user message (grade). Update the authoring checklist bullet and add a decision-log entry: "Grounding moved off Tag to a dedicated model (2026-07-19) — see `docs/superpowers/specs/2026-07-19-viva-grounding-materials-design.md`; files delivered as image_url, not text-extracted (extraction never existed)."

- [ ] **Step 3: CHANGELOG**

Under `[Unreleased]` in `CHANGELOG.md`:
```markdown
### Added
- Grounding materials: a dedicated model + admin library (Manage → Grounding) for viva reference material, replacing `viva_grounding` tags. Files are sent to the interviewer/grader as PDF image parts; the library shows a per-item token estimate and problem-reuse count.

### Changed
- Viva grounding is now attached to problems via a viva-only "Grounding materials" selector (with a per-problem token total) instead of the mixed Tags dropdown; the `viva_grounding` Tag kind is retired and existing tags backfilled.
```

- [ ] **Step 4: Backlog**

In `doc/backlog.md`, add: "Unify `llm_prompt` into a shared `LlmAsset` model (deferred alternative C from the grounding-materials spec) — `Tag` would become a pure label. Also: accurate page-count token estimate for grounding files via `pdf-reader` (v1 uses a byte-size proxy); grounding **image** files (png/jpeg) are stored but not yet sent to the model — extend `encode_pdf_part`."

- [ ] **Step 5: course-viva-prep skill**

Run: `grep -rin "viva_grounding\|grounding" ~/.claude/skills/course-viva-prep 2>/dev/null; find / -path '*course-viva-prep*' -name '*.md' 2>/dev/null`
If the skill authors `viva_grounding` tags programmatically, update those instructions to create `GroundingMaterial` records instead. If it only references grounding conceptually, update the wording. If the skill isn't found on disk, note it in the commit message as "verify course-viva-prep skill separately."

- [ ] **Step 6: Commit**

```bash
hg commit doc/Viva-Exam.md app/views/problems/_form.html.haml app/views/problems/_edit_help.html.haml app/views/problems/edit.html.haml config/locales/en.yml CHANGELOG.md doc/backlog.md \
  -m "Docs + changelog for grounding materials

Update Viva-Exam.md, in-app copy, locale, backlog; changelog entry.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Automated tests (consolidated, per tests-after preference)

Full Minitest coverage now that the feature works.

**Files:**
- Create: `test/fixtures/grounding_materials.yml`
- Create: `test/models/grounding_material_test.rb`
- Create: `test/services/llm/viva_grounding_assembly_test.rb`
- Create: `test/controllers/grounding_materials_controller_test.rb`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Fixtures**

Create `test/fixtures/grounding_materials.yml`:

```yaml
gm_dijkstra:
  title: Dijkstra notes
  body: "Shortest paths and priority queues."
  estimated_tokens: 0

gm_empty:
  title: Empty ref
  estimated_tokens: 0
```

Associate one with a problem via the HABTM join. Add to `test/fixtures/problems.yml` under an existing problem (e.g. `prob_add`) the line `grounding_materials: gm_dijkstra` (Rails resolves HABTM fixture labels). If inline HABTM fixtures misbehave, instead create `test/fixtures/grounding_materials_problems.yml` with `one: { grounding_material_id: <%= ActiveRecord::FixtureSet.identify(:gm_dijkstra) %>, problem_id: <%= ActiveRecord::FixtureSet.identify(:prob_add) %> }`.

- [ ] **Step 2: Model test**

Create `test/models/grounding_material_test.rb`:

```ruby
require "test_helper"

class GroundingMaterialTest < ActiveSupport::TestCase
  test "requires a title" do
    gm = GroundingMaterial.new(body: "x")
    assert_not gm.valid?
    assert gm.errors[:title].present?
  end

  test "grounding_text wraps body under a heading, nil when blank" do
    assert_nil GroundingMaterial.new(body: "").grounding_text
    gm = GroundingMaterial.new(body: "hello")
    assert_equal "## Grounding Material\n\nhello", gm.grounding_text
  end

  test "estimated_tokens recomputed from body after commit" do
    gm = GroundingMaterial.create!(title: "t", body: "a" * 40)
    assert_equal 10, gm.reload.estimated_tokens # 40 chars / 4
  end

  test "rejects non-pdf/image files" do
    gm = GroundingMaterial.new(title: "t")
    gm.files.attach(io: StringIO.new("x"), filename: "a.txt", content_type: "text/plain")
    assert_not gm.valid?
    assert gm.errors[:files].present?
  end

  test "has_and_belongs_to_many problems" do
    assert_includes grounding_materials(:gm_dijkstra).problems, problems(:prob_add)
  end
end
```

- [ ] **Step 3: Service assembly test**

Create `test/services/llm/viva_grounding_assembly_test.rb`:

```ruby
require "test_helper"

class VivaGroundingAssemblyTest < ActiveSupport::TestCase
  test "encode_pdf_part returns nil for unattached / non-pdf" do
    assert_nil Llm::Request.encode_pdf_part(nil)
    gm = GroundingMaterial.create!(title: "t")
    assert_nil Llm::Request.encode_pdf_part(gm.files.first)
  end

  test "grounding_file_parts encodes attached pdf as image_url" do
    gm = GroundingMaterial.create!(title: "t")
    gm.files.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")
    parts = gm.grounding_file_parts
    assert_equal 1, parts.length
    assert_equal "image_url", parts.first[:type]
    assert parts.first[:image_url].start_with?("data:application/pdf;base64,")
  end
end
```

- [ ] **Step 4: Controller test**

Create `test/controllers/grounding_materials_controller_test.rb`:

```ruby
require "test_helper"

class GroundingMaterialsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as("admin", "admin") } # helper defined in test/test_helper.rb

  test "unauthenticated is redirected" do
    get grounding_materials_path
    assert_redirected_to login_main_path
  end

  test "index lists materials" do
    get grounding_materials_path
    assert_response :success
    assert_select "td", text: "Dijkstra notes"
  end

  test "create with title" do
    assert_difference "GroundingMaterial.count", 1 do
      post grounding_materials_path, params: { grounding_material: { title: "New ref", body: "b" } }
    end
    assert_redirected_to grounding_materials_path
  end

  test "delete_file purges an attachment" do
    gm = GroundingMaterial.create!(title: "t")
    gm.files.attach(io: StringIO.new("%PDF"), filename: "a.pdf", content_type: "application/pdf")
    blob_id = gm.files.first.id
    assert_difference -> { gm.files.count }, -1 do
      delete delete_file_grounding_material_path(gm, blob_id: blob_id)
    end
  end
end
```

Note: `sign_in_as(user, password)` is defined in `test/test_helper.rb` and used across `test/controllers/` (see `tags_controller_test.rb`). That file also models the authorization assertions worth mirroring — unauthenticated → `login_main_path`, non-admin (`sign_in_as("john", "hello")`) → `list_main_path`.

- [ ] **Step 5: Run the tests**

Run:
```bash
bin/rails test test/models/grounding_material_test.rb test/services/llm/viva_grounding_assembly_test.rb test/controllers/grounding_materials_controller_test.rb
```
Expected: all pass. Then run the fuller suite to catch regressions:
```bash
bin/rails test
```
Expected: green (or only pre-existing unrelated failures).

- [ ] **Step 6: Commit**

```bash
hg add test/fixtures/grounding_materials.yml test/models/grounding_material_test.rb test/services/llm/viva_grounding_assembly_test.rb test/controllers/grounding_materials_controller_test.rb
hg commit test/fixtures/grounding_materials.yml test/fixtures/problems.yml test/models/grounding_material_test.rb test/services/llm/viva_grounding_assembly_test.rb test/controllers/grounding_materials_controller_test.rb \
  -m "Tests for grounding materials

Model, service assembly, and controller coverage.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation

- Run `bundle exec rubocop` on the new files and fix offenses (rubocop-rails-omakase).
- Consider `hg push` (mirrors both bookmarks) once the branch is reviewed — **only when the user asks**.
- Merge to `chula_cp` at a logical stopping point via `hg update chula_cp && hg merge master && hg commit` (never commit directly on `chula_cp`).
