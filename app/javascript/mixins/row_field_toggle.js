export const rowFieldToggle = (superclass) => class extends superclass {

  // given form target and records id
  // it changed the action url to match the id and submit the form
  // it is assumed that the placeholder id of the form's action url is -123
  submitToggleForm(form,id) {
    form.dataset.orig_action = form.action
    form.action = form.action.replace(-123,id)
    form.requestSubmit()
  }

  // reset the form back to the original action url
  resetToggleForm(event) {
    const form = event.target
    form.action = form.dataset.orig_action
    if (form.dataset.tableReloadId) {
      $(`#${form.dataset.tableReloadId}`).DataTable().ajax.reload()
    }
  }

  //this function is for submitting a form
  confirmSubmit(form,event) {
    if ('formConfirm' in event.target.dataset) {
      form.dataset.turboConfirm = event.target.dataset.formConfirm
    } else {
      form.removeAttribute('data-turbo-confirm')
    }
    form.requestSubmit()
  }


  // generic function for handling form submit via turbo
  // when response is OK, it will get the datatable api
  // and make ajax refresh
  //
  //   "table_id" should be jQuery selector that selects a atable (e.g., '#main-table')
  genericSubmitEnd(event,table_id) {
    if (event.detail.fetchResponse.response.ok) {
      table = new DataTable.Api(table_id)
      table.ajax.reload()
    }
  }
  
};
