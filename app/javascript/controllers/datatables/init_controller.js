import { Controller } from "@hotwired/stimulus";
import { configs } from "controllers/datatables/configs"

/**
 * usage: connect this controller to an enclosing tag that contains a table element
 *   that will be made into a datatable, like the following HAML
 *
 *       .tab-content{ data: {
 *           controller: 'datatables--init',
 *           'datatables--init-config-name-value': 'contestManageUser',
 *           'datatables--init-ajax-url-value': show_users_query_contest_path(@contest),
 *           action: 'datatable:reload@window->datatables--init#reload'
 *
 *  Write a config in /app/javascript/controllers/datatables/configs.js
 *  which may include columns from /app/javascript/controllers/datatables/columns.js
 *
 *  If ajax is needed, we can put the url helper as data-datatables--init-ajax-url-value
 *  since we cannot use url helper inside the javascript
 */
export default class extends Controller {
  static values = { 
    configName: String,
    ajaxUrl: String,
  }

  connect() {
    // tables is an array of DataTable object
    this.tables = [];

    // build the config, see the default behavior from these protected method
    const baseConfig = this._getBaseConfig();
    const finalConfig = this._buildFinalConfig(baseConfig);

    // build array of table elements that we should initialize
    let table_elements
    if (this.element.tagName.toLowerCase() === 'table') {
      // Case 1: Controller attached to the table itself.
      table_elements = [this.element];
    } else {
      // Case 2: Controller attached to enclosing elements
      table_elements = this.element.querySelectorAll('table');
    }

    // Initialize DataTable for each table found.
    table_elements.forEach(element => {
      this.tables.push($(element).DataTable(finalConfig));
    });

    // append to windows.tables
    window.tables = window.tables || []
    window.tables = window.tables.concat(this.tables)
  }

  // --- HOOK FUNCTIONS FOR SUBCLASS ---
  // These functions works by itself but we can override
  // it in a subclass when the need arise.
  /**
   * Fetches the base configuration object from the configs object (in datatables/configs.js)
   * @returns {object}
   */
  _getBaseConfig() {
    return configs[this.configNameValue] || configs.default;
  }

  /**
   * Assembles the final configuration object before initialization.
   * This is the main orchestrator method that subclasses can override
   * if they need to change the entire assembly logic.
   * @param {object} baseConfig The config from getBaseConfig()
   * @returns {object} The final config for DataTables.
   */
  _buildFinalConfig(baseConfig) {
    let finalConfig = { ...baseConfig };

    // This logic is now delegated to other hook methods
    finalConfig.columns = this._buildColumns(baseConfig);
    finalConfig.ajax = this._buildAjaxOptions(baseConfig);

    return finalConfig;
  }

  /**
   * Hook for building the 'columns' array.
   * The default behavior is to just use the columns from the config.
   * @param {object} baseConfig The config from getBaseConfig()
   * @returns {array} The columns definition for DataTables.
   */
  _buildColumns(baseConfig) {
    return baseConfig.columns;
  }

  /**
   * Hook for building the 'ajax' options object.
   * The default behavior is to merge the ajaxUrlValue.
   * @param {object} baseConfig The config from getBaseConfig()
   * @returns {object} The ajax options for DataTables.
   */
  _buildAjaxOptions(baseConfig) {
    if (this.hasAjaxUrlValue && typeof baseConfig.ajax === 'object') {
      return {
        ...baseConfig.ajax,
        url: this.ajaxUrlValue
      };
    }
    return baseConfig.ajax;
  }

  // this functions reload a datatable in this.table that has it's node() id in event.detail.table
  // Canonically, we can trigger this function by connecting it to an action but mostly we connect it
  // with  action: 'datatable:reload@window->datatables--init#reload'
  // and let the `event_dispatcher` turbo_stream fire the datatable:reload event with event_detail parameters
  reload(event) {
    // Get the string of space-separated table names.
    const targetNamesStr = event.detail?.table;

    // If a string of names is provided, split it into an array.
    // Otherwise, targetTables will be null.
    const targetTables = targetNamesStr ? targetNamesStr.split(' ') : null;

    this.tables.forEach(table => {
      // 1. No specific tables were targeted (targetTables is null).
      // 2. This table's id is included in the list of targeted tables.
      if (!targetTables || targetTables.includes(table.table().node().id)) {
        // 'null, false' reloads data from the server but keeps the user on the current page
        table.ajax.reload(null, false)
      }
    });
  }

  redraw(event) {
    this.tables.forEach(table => {
      table.draw();
    });
  }
}
