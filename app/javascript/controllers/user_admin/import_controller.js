import { Controller } from "@hotwired/stimulus"

// Import Users page: the Check button copies the visible form into a hidden
// form that posts to check_list (Turbo Stream into #import-check).
export default class extends Controller {
  static targets = ["list", "addToGroup", "groupId", "checkForm", "checkList",
                    "checkAddToGroup", "checkGroupId", "panel", "stale"]

  connect() {
    this.checked = null
    // select2 fires jQuery events, not native ones; jQuery is global here.
    this.onGroupSelect = () => this.markStale()
    $(this.groupIdTarget).on('select2:select', this.onGroupSelect)
  }

  disconnect() {
    $(this.groupIdTarget).off('select2:select', this.onGroupSelect)
  }

  check() {
    this.checkListTarget.value = this.listTarget.value
    this.checkAddToGroupTarget.value = this.addToGroupTarget.checked ? '1' : '0'
    this.checkGroupIdTarget.value = this.groupIdTarget.value
    this.checked = this.currentValues()
    this.staleTarget.classList.add('d-none')
    this.checkFormTarget.requestSubmit()
  }

  currentValues() {
    return [this.listTarget.value, this.addToGroupTarget.checked, this.groupIdTarget.value].join('\u0000')
  }

  // After a Check: show the note only while the form differs from what was
  // checked; changing it back hides the note again.
  markStale() {
    if (this.checked === null) return
    this.staleTarget.classList.toggle('d-none', this.currentValues() === this.checked)
  }
}
