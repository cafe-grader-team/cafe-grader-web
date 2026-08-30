// this controllers ensures that the tooltip is intialized
// we should attach this controller to the turbo-frame that is replaced by
// turbo action, so that the tooltip created by the new turbo-frame is initialized
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    this.handleFrameHasLoaded()
  }

  handleFrameHasLoaded = () => {
    this.initializeTooltips();
    this.initializePopovers();
    this.initializeSelect2();
    this.initializeTempusDominus();
  }


  initializeTooltips() {
    // Standard tooltip triggers, PLUS any element with data-bs-title that uses
    // data-bs-toggle for some other purpose (offcanvas, dropdown, modal, …) —
    // since data-bs-toggle holds a single value, those elements can't say
    // `="tooltip"` but still want a tooltip on hover. Popover triggers are
    // excluded: their data-bs-title is the popover's own heading, and
    // Bootstrap allows only one component instance per element — a tooltip
    // bound first would block the popover (console: "Bootstrap doesn't allow
    // more than one instance per element").
    const standard = this.element.querySelectorAll('[data-bs-toggle="tooltip"]');
    const piggybacked = this.element.querySelectorAll('[data-bs-title][data-bs-toggle]:not([data-bs-toggle="tooltip"]):not([data-bs-toggle="popover"])');
    const all = [...standard, ...piggybacked];

    this.tooltipInstances = all.map(el => new bootstrap.Tooltip(el));
  }

  initializePopovers() {
    const popoverTriggerList = this.element.querySelectorAll('[data-bs-toggle="popover"]');

    // Create new popover instances for the current content.
    // data-bs-content-selector="#id": take the popover body from an element
    // rendered elsewhere on the page (hidden) instead of an HTML blob in
    // data-bs-content — no escaping-HTML-into-an-attribute, and Bootstrap's
    // sanitizer allowlist doesn't apply to element content. Cloned per show,
    // because Bootstrap moves element content into the tip and destroys the
    // tip on hide.
    this.popoverInstances = Array.from(popoverTriggerList).map(popoverTriggerEl => {
      const options = {};
      const selector = popoverTriggerEl.dataset.bsContentSelector;
      const source = selector && document.querySelector(selector);
      if (source) {
        options.html = true;
        options.content = () => {
          const clone = source.cloneNode(true);
          clone.hidden = false;   // the source is rendered hidden; the copy must not be
          return clone;
        };
      }
      return new bootstrap.Popover(popoverTriggerEl, options);
    });
  }

  initializeSelect2() {
    $(".select2").select2({
      theme: "bootstrap-5",
      templateResult: this.formatArchivableOption,
      templateSelection: this.formatArchivableOption,
    });
    // Bridge select2's jQuery-triggered `select2:select` event to a native
    // `change` event. select2 v4 dispatches its events through jQuery, which
    // does NOT always reach native addEventListener handlers — and Stimulus'
    // `data-action="change->..."` uses native listeners. Without this bridge,
    // a select2-styled dropdown's selection silently fails to trigger
    // Stimulus actions. Namespaced .cafe_bridge so re-init doesn't stack
    // duplicate handlers.
    $(".select2").off("select2:select.cafe_bridge")
                 .on("select2:select.cafe_bridge", (event) => {
                   event.target.dispatchEvent(new Event("change", { bubbles: true }));
                 });
  }

  // Render a muted "archived" pill on options flagged data-archived="true"
  // (disabled/archived groups in the report filters, which — under the 3b
  // authorization model — appear only for editors, who can still report on
  // them). A plain no-op for every other option, so it's safe on all select2s.
  formatArchivableOption(state) {
    if (!state.id || !state.element) return state.text;
    if (state.element.dataset && state.element.dataset.archived === "true") {
      return $("<span>").text(state.text).append(
        ' <span class="badge bg-secondary-subtle text-secondary border border-secondary-subtle rounded-pill">archived</span>'
      );
    }
    return state.text;
  }

  initializeTempusDominus() {
    const tdTriggerList = this.element.querySelectorAll('.tempus-dominus')

    // Create new tempus dominus instances for the current content
    this.tdInstances = Array.from(tdTriggerList).map(tdTriggerEl => {
      // set the option to the template given by data-td-template
      let options = {}
      const templateName = tdTriggerEl.dataset.tdTemplate
      if (templateName) {
        options = structuredClone(cafe.config.td[templateName])
      } else {
        // default to date
        options = structuredClone(cafe.config.td.date)
      }
      return new TempusDominus(tdTriggerEl, options)
    });
  }

  disconnect() {
  }
}

