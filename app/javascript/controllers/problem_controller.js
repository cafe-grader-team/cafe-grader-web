import { Controller } from "@hotwired/stimulus"
import { rowFieldToggle } from "mixins/row_field_toggle";

export default class extends rowFieldToggle(Controller) {
  static targets = ["toggleAvailableForm", "toggleViewTestcaseForm",
                    "problemDate","datasetSelect","datasetSelectForm", "activeTabInput",
                    "datasetSettings","datasetTestcases","datasetFiles","dataset"
                   ]
  connect() {
    //if (typeof page_init === "function")
    //  page_init()
    //this.element.addEventListener("turbo:frame-load", this.handleFrameHasLoaded);
  }


  // for toggling of available and view testcase in the problem index page
  toggle(event) {
    event.target.disabled = true
    const recId = event.target.dataset.rowId
    const field = event.target.dataset.field
    const form = field === 'available'     ? this.toggleAvailableFormTarget :
                 field === 'view_testcase' ? this.toggleViewTestcaseFormTarget :
                 null
    this.submitToggleForm(form,recId)
  }

  // ---- Problem/Edit page ---------
  // on dataset card, activate when a dropdown of a dataset list is changed
  // submit a form 
  viewDataset(event) {
    const form = this.datasetSelectFormTarget
    form.requestSubmit()
  }

  // event handling binded with bulk manage form submit
  bulkManageSubmitEnd(event) {
    this.genericSubmitEnd(event,'#main-table')
    if (event.detail.fetchResponse.response.ok) {
      document.querySelectorAll('.manage-action').forEach(cb => cb.checked = false);
    }
  }

}
