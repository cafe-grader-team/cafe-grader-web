import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "useOption", "groupSelect", "idSelect", "tagSelect" ]

  connect() {
    // Dispatch the initial state so listeners can load with the default values
    this.filterChanged()

    // select2 use jQuery event system
    // I have tried using this.groupSelectTarget.addEventListener or using data-action but it does not work
    $(this.groupSelectTarget).on('change', () => { this.dispatchChange() });
    $(this.idSelectTarget).on('change', () => { this.dispatchChange() });
    $(this.tagSelectTarget).on('change', () => { this.dispatchChange() });
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
    $(this.idSelectTarget).prop('disabled', selectedValue !== 'ids').trigger('change');
    $(this.groupSelectTarget).prop('disabled', selectedValue !== 'groups').trigger('change');
    $(this.tagSelectTarget).prop('disabled', selectedValue !== 'tags').trigger('change');
  }

  /**
   * Dispatches a custom event with the current filter parameters.
   *   instead of firing a real event, we decided to store it
   *   dirtily on window.problemFilterParams
   *
   *   window.problemFilterParams then can be used by non-stimulus JS such as DataTables.ajax
   */
  dispatchChange() {
    console.log('changed')
    window.problemFilterParams = this.params
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
      'probs[use]': this.selectedOptionValue,
      'probs[ids][]': $(this.idSelectTarget).val(),
      'probs[group_ids][]': $(this.groupSelectTarget).val(),
      'probs[tag_ids][]': $(this.tagSelectTarget).val()
    };
  }
}
