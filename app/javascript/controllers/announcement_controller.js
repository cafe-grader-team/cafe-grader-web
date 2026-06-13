import { Controller } from "@hotwired/stimulus";
import { rowFieldToggle } from "mixins/row_field_toggle";

export default class extends rowFieldToggle(Controller) {
  static targets = ["togglePublishedForm", "toggleFrontForm",
                   ]

  toggle(event) {
    event.target.disabled = true
    const recId = event.target.dataset.rowId
    const field = event.target.dataset.field
    const form = field === 'published' ? this.togglePublishedFormTarget :
                 field === 'front'     ? this.toggleFrontFormTarget :
                 null
    this.submitToggleForm(form,recId)
  }

}
