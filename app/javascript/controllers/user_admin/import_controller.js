import { Controller } from "@hotwired/stimulus"

// Import Users page: the Check button copies the visible form into a hidden
// form that posts to check_list (Turbo Stream into #import-check).
export default class extends Controller {
  static targets = ["list", "addToGroup", "groupId", "checkForm", "checkList",
                    "checkAddToGroup", "checkGroupId", "panel", "stale"]

  check() {
    this.checkListTarget.value = this.listTarget.value
    this.checkAddToGroupTarget.value = this.addToGroupTarget.checked ? '1' : '0'
    this.checkGroupIdTarget.value = this.groupIdTarget.value
    this.staleTarget.classList.add('d-none')
    this.checkFormTarget.requestSubmit()
  }

  // Typing after a Check: tell the user the result no longer matches.
  markStale() {
    if (this.panelTarget.children.length > 0) this.staleTarget.classList.remove('d-none')
  }
}
