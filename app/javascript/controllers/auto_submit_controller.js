import { Controller } from "@hotwired/stimulus"

// Submits the form it sits on when a control inside fires
// `change->auto-submit#submit` — a select that acts as navigation, e.g. the
// contest picker on the Report pages (report/_page_header). Turbo drive is
// off, so a GET form here is a plain page load.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
