import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "useOption", "groupSelect", "onlyUsers" ]

  connect() {
    // Dispatch the initial state so listeners can load with the default values
    this.dispatchChange()
    $(this.groupSelectTarget).on('change', () => { this.dispatchChange() });
  }

  /**
   * This action is called any time an input changes.
   */
  filterChanged() {
    this.dispatchChange()
  }

  /**
   * Dispatches a custom event with the current filter parameters.
   *   instead of firing a real event, we decided to store it
   *   dirtily on window.userFilterParams
   *
   *   window.userFilterParams then can be used by non-stimulus JS such as DataTables.ajax
   */
  dispatchChange() {
    window.userFilterParams = this.params
  }

  /**
   * A getter that builds and returns an object of the current filter values.
   * @returns {object}
   */
  get params() {
    const selectedRadio = this.useOptionTargets.find(radio => radio.checked)

    return {
      'users[use]': selectedRadio ? selectedRadio.value : 'all',
      'users[group_ids]': $(this.groupSelectTarget).val(),
      'users[only_users]': this.onlyUsersTarget.checked,
    }
  }
}
