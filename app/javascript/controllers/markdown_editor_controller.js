import { Controller } from "@hotwired/stimulus"
import ace from "ace-builds"
import "ace-mode-markdown"
import "ace-theme-github"

// Markdown editing aid for the long prompt / statement textareas: the viva
// Examiner briefing and Scenario (problems/_form), the viva_conduct / AI-helper
// tag prompt (tags/_form) and the grounding body (grounding_materials/_form).
//
// Wraps the <textarea> in an Ace editor (markdown highlighting, soft wrap,
// light theme — these are prose, not code) and adds an Edit / Preview toggle.
// Preview posts the text to `previewUrl` (MarkdownController#preview), which
// renders with the same Redcarpet helper the app uses elsewhere, so the pane
// shows what the app would show — not a second client-side renderer.
//
// The textarea stays in the DOM (hidden) and is kept in sync on every edit, so
// form submission, server-side validation errors and Turbo re-renders need no
// special handling. External writers (grounding-draft "Copy draft into Body")
// keep setting textarea.value — they just dispatch a `change` event and we
// pull the new value into Ace.
//
// Wiring (see ApplicationHelper#markdown_editor_data):
//   wrapper: data-controller="markdown-editor" data-markdown-editor-preview-url-value="/markdown/preview"
//   textarea: data-markdown-editor-target="source"; its rows attribute sets the editor's min height.
export default class extends Controller {
  static targets = ["source"]
  static values = {
    previewUrl: String,
    maxLines: { type: Number, default: 40 }
  }

  connect() {
    this.#buildChrome()
    this.#initEditor()
    this.onExternalChange = () => this.#pullFromSource()
    this.sourceTarget.addEventListener("change", this.onExternalChange)
  }

  disconnect() {
    this.sourceTarget.removeEventListener("change", this.onExternalChange)
    this.editor?.destroy()
    this.editor = null
    this.chrome?.remove()
    this.sourceTarget.classList.remove("d-none")
  }

  // --- actions (buttons are built in #buildChrome) ---

  showEdit() {
    this.#setMode("edit")
    this.editor.focus()
  }

  async showPreview() {
    this.#setMode("preview")
    this.previewPane.innerHTML = '<div class="text-secondary small">Rendering…</div>'
    try {
      const body = new FormData()
      body.append("text", this.editor.getValue())
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        body,
        headers: { "Accept": "text/html", ...(token ? { "X-CSRF-Token": token } : {}) },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      this.previewPane.innerHTML = await response.text()
    } catch (error) {
      this.previewPane.innerHTML = '<div class="text-danger small">Preview failed. Are you still logged in?</div>'
      console.error("markdown preview failed", error)
    }
  }

  // --- private ---

  #buildChrome() {
    const source = this.sourceTarget
    source.classList.add("d-none")

    this.chrome = document.createElement("div")
    this.chrome.className = "markdown-editor border rounded"
    this.chrome.innerHTML = `
      <div class="markdown-editor__bar d-flex align-items-center gap-2 px-2 py-1 border-bottom bg-body-tertiary">
        <ul class="nav nav-pills gap-1">
          <li class="nav-item"><button type="button" class="nav-link active" data-mode="edit">Edit</button></li>
          <li class="nav-item"><button type="button" class="nav-link" data-mode="preview">Preview</button></li>
        </ul>
        <span class="ms-auto small text-secondary">Markdown</span>
      </div>
      <div class="markdown-editor__ace"></div>
      <div class="markdown-editor__preview markdown-content p-3 d-none"></div>`
    source.insertAdjacentElement("afterend", this.chrome)

    this.editorPane  = this.chrome.querySelector(".markdown-editor__ace")
    this.previewPane = this.chrome.querySelector(".markdown-editor__preview")
    this.chrome.querySelector('[data-mode="edit"]').addEventListener("click", () => this.showEdit())
    this.chrome.querySelector('[data-mode="preview"]').addEventListener("click", () => this.showPreview())
  }

  #initEditor() {
    const source = this.sourceTarget
    const rows = parseInt(source.getAttribute("rows"), 10) || 12
    this.editor = ace.edit(this.editorPane, {
      mode: "ace/mode/markdown",
      theme: "ace/theme/github",
      minLines: rows,
      maxLines: Math.max(rows, this.maxLinesValue),
      wrap: true,
      showPrintMargin: false,
      showGutter: false,
      highlightActiveLine: false,
      tabSize: 2,
      useSoftTabs: true,
      fontSize: "0.875rem"
    })
    this.editor.renderer.setPadding(10)
    this.editor.session.setValue(source.value)
    this.editor.session.on("change", () => { source.value = this.editor.getValue() })
    // a11y: keep the field's label pointing at something focusable
    const label = source.id && document.querySelector(`label[for="${source.id}"]`)
    if (label) label.addEventListener("click", (e) => { e.preventDefault(); this.editor.focus() })
  }

  #pullFromSource() {
    if (!this.editor || this.editor.getValue() === this.sourceTarget.value) return
    this.editor.session.setValue(this.sourceTarget.value)
    this.showEdit()
  }

  #setMode(mode) {
    this.editorPane.classList.toggle("d-none", mode !== "edit")
    this.previewPane.classList.toggle("d-none", mode !== "preview")
    this.chrome.querySelectorAll(".nav-link").forEach(b => b.classList.toggle("active", b.dataset.mode === mode))
    if (mode === "edit") this.editor.resize()
  }
}
