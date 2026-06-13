import { Controller } from "@hotwired/stimulus"
import { rowFieldToggle } from "mixins/row_field_toggle";

export default class extends rowFieldToggle(Controller) {

  static targets = ["usersCommand", "userForm", "userFormUserID", "userFormCommand" ,
                    "problemsCommand", "problemForm", "problemFormProblemID", "problemFormCommand" ,
                    "toggleForm",
                   ]

  connect() {
    //console.log('stimulus group',this.element)

    //fetch("/groups/10/show_users_query", {
    //  method: "POST",
    //}).then(r => r.text())
    //  .then(html => console.log(html))
  }

  toggle(event) {
    event.target.disabled = true
    const recId = event.target.dataset.rowId
    const form = this.toggleFormTarget
    this.submitToggleForm(form,recId)
  }

  setUsersCommand(event) {
    const command = this.usersCommandTarget
    command.value = event.target.dataset.value
  }

  postUserAction(event) {
    event.preventDefault() //this comes from a link, so we prevent default
    const form = this.userFormTarget
    const user_id = this.userFormUserIDTarget
    const command = this.userFormCommandTarget
    command.value = event.target.dataset.command
    user_id.value = event.target.dataset.rowId
    if ('formConfirm' in event.target.dataset) {
      form.dataset.turboConfirm = event.target.dataset.formConfirm
    } else {
      form.removeAttribute('data-turbo-confirm')
    }
    form.requestSubmit()
  }

  afterUserAction(event) {
    if (!event.detail.fetchResponse.response.redirected)
      $("#user_table").DataTable().ajax.reload()
  }


  afterUsersAdd(event) {
    if (!event.detail.fetchResponse.response.redirected) {
      $('#user_ids').val(null).trigger("change");
      $('#user_group_ids').val(null).trigger("change");
      const dt = $("#user_table").DataTable()
      dt.ajax.reload()
    }
  }

  setProblemsCommand(event) {
    const command = this.problemsCommandTarget
    command.value = event.target.dataset.value
  }

  postProblemAction(event) {
    event.preventDefault() //this comes from a link, so we prevent default
    const form = this.problemFormTarget
    const problem_id = this.problemFormProblemIDTarget
    const command = this.problemFormCommandTarget
    command.value = event.target.dataset.command
    problem_id.value = event.target.dataset.rowId
    if ('formConfirm' in event.target.dataset) {
      form.dataset.turboConfirm = event.target.dataset.formConfirm
    } else {
      form.removeAttribute('data-turbo-confirm')
    }
    form.requestSubmit()
  }

  afterProblemAction(event) {
    if (!event.detail.fetchResponse.response.redirected) {
      $("#problem_table").DataTable().ajax.reload()
    }
  }

  afterProblemsAdd(event) {
    if (!event.detail.fetchResponse.response.redirected) {
      $('#problem_ids').val(null).trigger("change");
      $('#problem_group_ids').val(null).trigger("change");
      $("#problem_table").DataTable().ajax.reload()
    }
  }

  test(event) {

  }

}
