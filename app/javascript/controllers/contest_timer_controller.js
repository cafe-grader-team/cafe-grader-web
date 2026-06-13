import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["counter"]

  connect() {
    if (this.hasCounterTarget) {
      this.update()
      this.timer = setInterval(() => {
        this.update()
      }, 500)
    }
  }

  disconnect() {
    clearInterval(this.timer)
  }


  // This is for update all counters of each contest
  update() {
    const now = new Date()

    this.counterTargets.forEach((element) => {
      const startTime = Date.parse(element.dataset.start)
      const stopTime = Date.parse(element.dataset.stop)

      if (now < startTime) {
        let text = humanizeTime(element.dataset.start, 'starts in ', 'started ')
        if ( (startTime - parseInt(element.dataset.startOffset) * 1000) < now) {
          text += ` (You have ${element.dataset.startOffset} seconds head start)`
        }
        element.textContent = text;
      } else {
        let text = humanizeTime(element.dataset.stop, 'ends in ', 'ended ')
        if (parseInt(element.dataset.extraTime) > 0) {
          const endWithExtraTimeAsDate = new Date(stopTime + parseInt(element.dataset.extraTime) * 1000 )
          const endWithExtraTime = humanizeTime(endWithExtraTimeAsDate.toISOString(), 'ends in ', 'ended ')
          text += ` <div class="fst-italic">(You have ${element.dataset.extraTime} seconds extra time, <span class="fw-bold">${endWithExtraTime}</span>)</div>`
        }
        element.innerHTML = text;
      }
    })
  }
}
