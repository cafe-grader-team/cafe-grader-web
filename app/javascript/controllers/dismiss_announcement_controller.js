import { Controller } from "@hotwired/stimulus"

// Handles dismissing the "Updated" badge on announcements via cookies.
// Attach to the .card element with data-controller="dismiss-announcement"
// and pass id/timestamp as values.
export default class extends Controller {
  static values = { id: Number, timestamp: Number }
  static targets = ["badge"]

  dismiss(event) {
    event.preventDefault()
    document.cookie = `dismissed_ann_${this.idValue}_${this.timestampValue}=true; path=/; max-age=86400`

    this.badgeTarget.style.display = "none"
    this.element.classList.remove("border-danger", "border-opacity-50")
  }
}
