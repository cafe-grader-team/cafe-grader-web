import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ 'selectForm' ]

  // trigger when the drop down item is selected
  // submit the form
  childSelect(event) {
    const form = this.selectFormTarget
    form.requestSubmit()
  }

}
