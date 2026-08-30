import { Controller } from "@hotwired/stimulus"

// "Copy draft into Body" for the grounding-material PDF extraction draft
// (design D4, docs/superpowers/specs/2026-07-20-viva-deployment-readiness-
// design.md). Deliberately client-side only and NEVER persists anything —
// it just prefills the Body textarea so the author reviews/edits before an
// explicit form Save. The draft <pre> is the source of truth for the copied
// text (read via textContent), so nothing needs to stay in sync across a
// Turbo re-render besides the two data-*-target attributes.
export default class extends Controller {
  static targets = ["draft", "body"]

  copyIntoBody() {
    if (!this.hasDraftTarget || !this.hasBodyTarget) return
    this.bodyTarget.value = this.draftTarget.textContent.trim()
    // The Body textarea is wrapped by markdown-editor (Ace); a `change` event
    // is how it learns about external writes like this one.
    this.bodyTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.bodyTarget.focus()
    this.bodyTarget.scrollIntoView({ behavior: "smooth", block: "center" })
  }
}
