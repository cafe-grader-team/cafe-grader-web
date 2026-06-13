import { Controller } from "@hotwired/stimulus"

// this controller will fire an event specificed in the controller
// It should not really be attached to existing element
// but it should be attached to a blank div that will be
// appended to a notification area (such as toast-area) by
//
//   render turbo_stream: turbo_stream.append('toast-area', partial: 'event_dispatcher', 
//     locals: {event_name: 'datatable:reload', event_detail: {any_detail: 'asdf'} })
export default class extends Controller {
  connect() {
    const eventName = this.element.dataset.eventName
    const eventDetail = JSON.parse(this.element.dataset.eventDetail || "{}")

    if (eventName) {
      // Dispatch a global event that any other controller can listen for
      const event = new CustomEvent(eventName, { detail: eventDetail, bubbles: true })
      window.dispatchEvent(event)
    }

    // This element has done its job, so we remove it
    this.element.remove()
  }
}
