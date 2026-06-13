import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "useOption", "fromId", "toId", "fromTime", "toTime" ]

  connect() {
    // Dispatch the initial state so listeners can load with the default values
    this.filterChanged()
  }

  /**
   * This action is called any time an input changes.
   */
  filterChanged() {
    this.toggleSelects()
    this.dispatchChange()
  }

  /**
   * A UX helper to enable the relevant select box and disable the others.
   */
  toggleSelects() {
    const selectedValue = this.selectedOptionValue;
    $(this.fromIdTarget).prop('disabled', selectedValue !== 'sub_id').trigger('change');
    $(this.toIdTarget).prop('disabled', selectedValue !== 'sub_id').trigger('change');
    $(this.fromTimeTarget).prop('disabled', selectedValue !== 'sub_time').trigger('change');
    $(this.toTimeTarget).prop('disabled', selectedValue !== 'sub_time').trigger('change');
  }

  /**
   * Dispatches a custom event with the current filter parameters.
   *   instead of firing a real event, we decided to store it
   *   dirtily on window.problemFilterParams
   *
   *   window.problemFilterParams then can be used by non-stimulus JS such as DataTables.ajax
   */
  dispatchChange() {
    window.submissionFilterParams = this.params
  }

  /**
   * Getter for the value of the currently selected radio button.
   * @returns {string}
   */
  get selectedOptionValue() {
    return this.useOptionTargets.find(radio => radio.checked)?.value;
  }

  /**
   * A getter that builds and returns an object of the current filter values.
   * @returns {object}
   */
  get params() {
    return {
      'sub_range[use]': this.selectedOptionValue,
      'sub_range[from_id]': this.fromIdTarget.value,
      'sub_range[to_id]': this.toIdTarget.value,
      'sub_range[from_time]': this.fromTimeTarget.value,
      'sub_range[to_time]': this.toTimeTarget.value,
    };
  }
}
