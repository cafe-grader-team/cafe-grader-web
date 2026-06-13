// after a timeout, click the button
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "refreshLink", "waitingText", "stopwatchText" ]

  // this is values that is read from data-editor-delay-value
  static values = {
    delay: { type: Number, default: 5000 }, // Default delay is 5000ms (5 secs), if delay is < 0, we won't start the timer
    timerTemplate: { type: String, default: 'Checking score in {{second}} seconds.'},
    stopwatchTemplate: { type: String, default: 'Running for {{second}} sconds.'},
  }

  connect() {
    if (this.delayValue > 0) {
      this.startTimer();
    } else  {
      //console.log('Timer not started.');
    }
  }

  // for starting auto refresh latest submission status
  startTimer() {
    // click the refresh button after 5 secs
    this.remainingSeconds = this.delayValue / 1000
    console.log('start refresh with ' + this.remainingSeconds)

    // init UI update
    this.updateCountdownText();
    this.updateAllStopwatches();

    // interval every 1 second
    this.refreshTimer = setInterval(() => {
      // update countdown
      this.remainingSeconds--;
      this.updateCountdownText();

      // update all stopwatches
      this.updateAllStopwatches();


      // click the refresh button when countdown finishes
      if (this.remainingSeconds <= 0) {
        //console.log('clicking...')
        clearInterval(this.refreshTimer)

        // click the refersh button
        if (this.hasRefreshLinkTarget) {
          this.refreshLinkTarget.click();
        }
      }
    }, 1000) // update every second
  }

  // render the waiting text
  updateCountdownText() {
    if (this.hasWaitingTextTarget) {
      const text = this.timerTemplateValue
        .replace('{{second}}',this.remainingSeconds)
      //console.log(text)
      this.waitingTextTarget.textContent = text
    }
  }

  // New method to iterate over all stopwatch targets
  updateAllStopwatches() {
    // Stimulus provides this.stopwatchTextTargets (plural) to loop through
    this.stopwatchTextTargets.forEach(target => {
      const startTimeString = target.dataset.startTime;
      const template = target.dataset.template || this.stopwatchTemplateValue

      if (startTimeString) {
        const startTime = new Date(startTimeString);
        const elapsedSeconds = Math.round((new Date() - startTime) / 1000);
        const text = template.replace('{{second}}', elapsedSeconds);
        target.textContent = text;
      }
    });
  }

  disconnect() {
    // Clear the timeout if the controller is ever disconnected from the DOM
    // This prevents memory leaks or unexpected clicks.
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }
}
