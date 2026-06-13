import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["usersCommand", "userForm", "userFormUserID", "userFormCommand",
    "problemsCommand", "problemForm", "problemFormProblemID", "problemFormCommand",
    "contestForm", "contestFormContestID", "contestFormCommand",
    "userExtraTimeForm", "userExtraTimeFormStart", "userExtraTimeFormEnd", "userExtraTimeFormRowID"
  ]

  connect() {
    window.user_table_init = false
    window.problem_table_init = false
  }

  setUsersCommand(event) {
    const command = this.usersCommandTarget
    command.value = event.target.dataset.value
  }

  postUserAction(event) {
    event.preventDefault()
    // event.currentTarget is the dom that has the action attached
    const form = this.userFormTarget
    const user_id = this.userFormUserIDTarget
    const command = this.userFormCommandTarget
    command.value = event.currentTarget.dataset.command
    user_id.value = event.currentTarget.dataset.rowId
    if ('formConfirm' in event.currentTarget.dataset) {
      form.dataset.turboConfirm = event.currentTarget.dataset.formConfirm
    } else {
      form.removeAttribute('data-turbo-confirm')
    }
    form.requestSubmit()
  }

  afterUsersAdd(event) {
    $('#user_ids').val(null).trigger("change");
    $('#user_group_ids').val(null).trigger("change");
  }

  setProblemsCommand(event) {
    const command = this.problemsCommandTarget
    command.value = event.target.dataset.value
  }

  postProblemAction(event) {
    event.preventDefault()
    const form = this.problemFormTarget
    const problem_id = this.problemFormProblemIDTarget
    const command = this.problemFormCommandTarget
    command.value = event.currentTarget.dataset.command
    problem_id.value = event.currentTarget.dataset.rowId
    form.requestSubmit()
  }

  afterProblemsAdd(event) {
    $('#problem_ids').val(null).trigger("change");
    $('#problem_group_ids').val(null).trigger("change");
  }

  //for contest
  postContestAction(event) {
    // event.target is the dom that emits the event
    // the parameter for the action is in data-* of  the dom
    // we copy the parameter and set the appropriate input
    // of the form
    const form = this.contestFormTarget
    const contest_id = this.contestFormContestIDTarget
    const command = this.contestFormCommandTarget
    command.value = event.target.dataset.command
    contest_id.value = event.target.dataset.rowId
    if ('formConfirm' in event.target.dataset) {
      form.dataset.turboConfirm = event.target.dataset.formConfirm
    } else {
      form.removeAttribute('data-turbo-confirm')
    }
    form.requestSubmit()
  }

  tabChange(event) {
    const tabButton = event.target
    if (tabButton.dataset.tableInit == "no") {
      $(`#${tabButton.dataset.tableId}`).DataTable().columns.adjust().draw()
      tabButton.dataset.tableInit == "yes"
    }
  }

  showExtraTimeDialog(event) {
    const form = this.userExtraTimeFormTarget
    const start_offset = this.userExtraTimeFormStartTarget
    const end_offset = this.userExtraTimeFormEndTarget
    const user = this.userExtraTimeFormRowIDTarget

    const user_id = event.currentTarget.dataset.rowId
    const currentStartOffset = event.currentTarget.dataset.startOffset
    const currentExtraTime = event.currentTarget.dataset.extraTime
    user.value = user_id


    event.preventDefault()
    const element = event.target

    bootbox.dialog({
      title: `Set extra times for ${event.currentTarget.dataset.login}`,
      message: `
        <div class="form-group">
          <label for="start-offset">Extra Time before Start (second)</label>
          <input type="number" class="form-control" id="start-offset" value="${currentStartOffset}">
        </div>
        <div class="form-group">
          <label for="end-offset">Extra Time After Finish (second)</label>
          <input type="number" class="form-control" id="end-offset" value="${currentExtraTime}" >
        </div> `,
      buttons: {
        cancel: {
          label: 'Cancel',
          className: 'btn-secondary'
        },
        ok: {
          label: 'OK',
          className: 'btn-primary',
          callback: function () {
            start_offset.value = $('#start-offset').val()
            end_offset.value = $('#end-offset').val()
            form.requestSubmit()
          }
        },

      }
    })

  }
}
