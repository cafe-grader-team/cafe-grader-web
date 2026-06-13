import { Controller } from "@hotwired/stimulus";
import { rowFieldToggle } from "mixins/row_field_toggle";

export default class extends rowFieldToggle(Controller) {
  static targets = ["userForm", "userFormUserID", "userFormCommand" ,
                   ]

  get userForm() {
    return {
      form: this.userFormTarget,
      userId: this.userFormUserIDTarget,
      command: this.userFormCommandTarget
    }
  }

  postUserAction(event) {
    // must call this one to prevent the link to scroll to the top
    event.preventDefault()

    const { form, userId, command } = this.userForm

    //set the command and user_id in the form
    command.value = event.target.dataset.command
    userId.value = event.target.dataset.rowId

    this.confirmSubmit(form,event)
  }

  afterUserAction(event) {
    $("#main-table").DataTable().ajax.reload()
  }
}
