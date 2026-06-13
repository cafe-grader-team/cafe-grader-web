import { Controller } from "@hotwired/stimulus"

// Hides form fields that don't apply when the problem's
// compilation_type is set to viva_exam. Viva problems are oral
// interviews; the student submits no code, so "Allowed Language"
// and "Submission filename" are noise.
//
// Wiring:
//   * The controller scope is the <turbo-frame> wrapping the form.
//   * Each conditional field's simple_form wrapper carries
//     data-viva-mode-toggle-target="hideForViva".
//   * Each compilation_type radio input carries
//     data-action="change->viva-mode-toggle#toggle".
//   * connect() runs toggle() once on initial render so the
//     persisted state is reflected without waiting for a click.
//
// We toggle the Bootstrap `d-none` class on the wrapper div rather
// than disabling inputs because the concept doesn't apply at all
// for viva — see commit history for the design discussion.
export default class extends Controller {
  static targets = ["hideForViva"]

  connect() {
    this.toggle()
  }

  toggle() {
    const checked = this.element.querySelector('input[name$="[compilation_type]"]:checked')
    const value   = checked?.value
    this.hideForVivaTargets.forEach(el => el.classList.toggle("d-none", value === "viva_exam"))

    // Broadcast the new compilation_type so listeners outside this
    // controller's scope (notably the dataset-mode-toggle controller
    // in the right-column dataset card) can react. Event name is
    // namespaced ("mode:") to avoid clashing with anything else.
    this.dispatch("compilation-type-changed", { detail: { value }, prefix: "mode" })
  }
}
