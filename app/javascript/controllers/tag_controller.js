import { Controller } from "@hotwired/stimulus"
import { rowFieldToggle } from "mixins/row_field_toggle";

export default class extends rowFieldToggle(Controller) {
  static targets = ["togglePublicForm", "togglePrimaryForm",
                   ]

  // for toggle of public and primary field
  // each field has its own form
  toggle(event) {
    event.target.disabled = true
    const recId = event.target.dataset.rowId
    const field = event.target.dataset.field
    const form = field === 'public'  ? this.togglePublicFormTarget :
                 field === 'primary' ? this.togglePrimaryFormTarget :
                 null
    this.submitToggleForm(form,recId)
  }

}
