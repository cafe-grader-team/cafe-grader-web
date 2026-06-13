import { Controller } from "@hotwired/stimulus"

// Reactive progressive disclosure for the dataset edit form on
// /problems/:id/edit. Hides sections that don't apply to the current
// problem.compilation_type / dataset.evaluation_type:
//
//   * hideForSelfContained — Manager section + main_filename select.
//     Managers are only used when compilation_type == :with_managers
//     (compiler.rb:87 / python.rb:24 gate the usage).
//   * hideUnlessCustomEval — Checker section.
//     Checker is only consulted when evaluation_type is one of
//     custom_cafe / custom_cms / custom_cms_raw.
//
// The Checker section is now ALWAYS rendered (no `if` in the partial)
// so the upload input exists in the DOM regardless of evaluation_type.
// We just hide it visually when it doesn't apply. This fixes issue #48
// where users couldn't upload a checker until they had first saved the
// dataset with a custom_* evaluation_type.
//
// compilation_type lives in the left-column problem form (different
// Turbo Frame), so we receive it via a window event dispatched by the
// viva-mode-toggle controller. Initial value is server-rendered via
// data-dataset-mode-toggle-compilation-type-value=... so first paint
// is correct without waiting for the first click.
//
// evaluation_type is local — read directly from the targeted select.
export default class extends Controller {
  static targets = [
    "evaluationType",
    "hideForSelfContained",
    "hideUnlessCustomEval"
  ]
  static values = { compilationType: String }

  connect() {
    this.refresh()
  }

  // Called from data-action when viva-mode-toggle dispatches its
  // mode:compilation-type-changed event on window.
  syncCompilationType(event) {
    this.compilationTypeValue = event.detail?.value ?? ""
    this.refresh()
  }

  // Stimulus auto-fires when targets connect (initial paint or after
  // a Turbo Frame refresh of the dataset settings/files frames).
  evaluationTypeTargetConnected(el) {
    el.addEventListener("change", this.refresh.bind(this))
    this.refresh()
  }

  evaluationTypeTargetDisconnected(el) {
    el.removeEventListener("change", this.refresh.bind(this))
  }

  hideForSelfContainedTargetConnected() { this.refresh() }
  hideUnlessCustomEvalTargetConnected() { this.refresh() }

  refresh() {
    const isSelfContained = this.compilationTypeValue === "self_contained"
    const evalType = this.hasEvaluationTypeTarget ? this.evaluationTypeTarget.value : null
    const needsChecker = ["custom_cafe", "custom_cms", "custom_cms_raw"].includes(evalType)

    this.hideForSelfContainedTargets.forEach(el =>
      el.classList.toggle("d-none", isSelfContained))
    this.hideUnlessCustomEvalTargets.forEach(el =>
      el.classList.toggle("d-none", !needsChecker))
  }
}
