// app/javascript/controllers/tabs_controller.js
import { Controller } from "@hotwired/stimulus"
//import { Tab } from "bootstrap" // Good practice to import for Bootstrap's JS events

export default class extends Controller {
  static targets = [ "activeTabInput" ]

  connect() {
    // Listen to 'shown.bs.tab' events that bubble up to this controller's element
    this.element.addEventListener('shown.bs.tab', (event) => {
      // event.target is the tab link/button that was shown
      this.setActiveTab(event.target.dataset.bsTarget)
    })
  }

  setActiveTab(tabId) {
    // this.hasActiveTabInputTarget checks if at least one such target exists
    if (this.hasActiveTabInputTarget) {
      // this.activeTabInputTargets is an array of all DOM elements
      // matching data-bs-tabs-target="activeTabInput" within this controller's scope.
      this.activeTabInputTargets.forEach(inputElement => {
        inputElement.value = tabId
      })
    }
  }

  disconnect() {
    this.element.removeEventListener('shown.bs.tab', (event) => {
      this.setActiveTab(event.target.id) // Or just a placeholder if not needed
    })
  }
}
