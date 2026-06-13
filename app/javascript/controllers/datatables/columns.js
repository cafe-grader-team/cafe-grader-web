import * as cafe from 'cafe_bundle'

export const renderers = {
  user_prob: (data, type, row, meta) => {
    let uc = window.userCount[row['id']] || '-'
    let pc = window.probCount[row['id']] || '-'
    if (type == 'display' || type == 'filter')
      return uc + ' : ' + pc

    return parseFloat(`${uc}.${pc}`)
  },
  // -------- contests render -------------
  startStopOffsetRender: (data, type, row, meta) => {
    const start_offset = row['start_offset_second']
    const extra_time = row['extra_time_second']
    return `<span class="d-inline-flex align-items-center">${start_offset} : ${extra_time} ` +
      `<a class="d-inline-flex align-items-center text-decoration-none" href='#' data-row-id="${row['id']}" data-login="${row['login']}" data-start-offset="${start_offset}" data-extra-time="${extra_time}" data-action="click->contest#showExtraTimeDialog">` +
      `<span class="mi md-18 mx-1">edit</span></a>` +
      `<span>`
  },
  userActionRenderer: (data, type, row, meta) => {
    // only render for display
    if (type != 'display') return ''

    // roles and labels
    const isEditor = row['role'] === 'editor';
    const toggleRoleLabel = isEditor ? 'Set as User' : 'Set as Editor';
    const toggleRoleCommand = isEditor ? 'make_user' : 'make_editor';
    const toggleRoleIcon = isEditor ? 'person' : 'shield_person';

    return `
      <div class="d-flex align-items-center">
        <span>&nbsp; </span>
        <div class="dropdown d-flex align-items-center">
          <a class="btn btn-outline-secondary border-0 link-flex rounded-1 p-1" type="button" data-bs-toggle="dropdown" aria-expanded="false">
            <span class="mi">more_horiz</span>
          </a>
          <ul class="dropdown-menu dropdown-menu-end border-0 shadow-sm">
            <li><h6 class="dropdown-header">Actions for ${row['login']}</h6></li>
            <li>
              <a class="dropdown-item d-flex align-items-center gap-2" href="#" 
                 data-action="click->contest#postUserAction" 
                 data-row-id="${row['user_id']}" 
                 data-command="clear_ip">
                <span class="mi md-18 text-warning">lock_reset</span>
                Clear Session Lock
              </a>
            </li>
            <li>
              <a class="dropdown-item d-flex align-items-center gap-2" href="#" 
                 data-action="click->contest#postUserAction" 
                 data-row-id="${row['user_id']}" 
                 data-command="${toggleRoleCommand}">
                <span class="mi md-18 text-info">${toggleRoleIcon}</span>
                ${toggleRoleLabel}
              </a>
            </li>
            <li><hr class="dropdown-divider"></li>
            <li>
              <a class="dropdown-item d-flex align-items-center gap-2 text-danger" href="#" 
                 data-action="click->contest#postUserAction" 
                 data-row-id="${row['user_id']}" 
                 data-command="remove"
                 data-form-confirm="Remove ${row['login']} from this contest?">
                <span class="mi md-18">person_remove</span>
                Remove from Contest
              </a>
            </li>
          </ul>
        </div>
      </div>
    `;
  },
  problemActionRenderer: (data, type, row, meta) => {
    if (type != 'display') return ''

    return `
      <div class="d-flex gap-1 justify-content-end">
        <button class="btn btn-outline-secondary border-0 py-1 px-2"
           data-action="click->contest#postProblemAction" 
           data-row-id="${row['problem_id']}" 
           data-command="moveup" title="Move Up">
          <span class="mi">arrow_upward</span>
        </button>
        <button class="btn btn-outline-secondary border-0 py-1 px-2"
           data-action="click->contest#postProblemAction" 
           data-row-id="${row['problem_id']}" 
           data-command="movedown" title="Move Down">
          <span class="mi">arrow_downward</span>
        </button>
        <button class="btn btn-outline-danger border-0 py-1 px-2"
           data-action="click->contest#postProblemAction" 
           data-row-id="${row['problem_id']}" 
           data-command="remove"
           data-form-confirm="Remove ${row['name']} from this contest?" title="Remove from Contest">
          <span class="mi">close</span>
        </button>
      </div>
    `;
  },
  roleActionButton: (data, type, row, meta) => {
    let result = ''
    if (row['role'] != 'editor')
      result += cafe.dt.render.button('as editor', { element_type: 'link', className: 'link-success', action: 'contest#postUserAction', command: 'make_editor' })(row['user_id'], type, row, meta)
    if (row['role'] != 'user') {
      if (result != '') result += ' | '
      result += cafe.dt.render.button('as user', { element_type: 'link', className: 'link-info', action: 'contest#postUserAction', command: 'make_user' })(row['user_id'], type, row, meta)
    }
    return result
  },
  humanizeTimeRender: (data, type, row, meta) => {
    if (!data) return ''
    if (type == 'display' || type == 'filter')
      return humanizeTime(data)

    //for sort, we just return the data which is supposed to be iso8601
    return data
  }
}

// columns for each tables
// reuse this if available
export const columns = {
  // generic columns
  id: { data: 'id', title: 'ID' },
  // model specific columns
  solidQueueJob: {
    queue: { data: 'queue_name', title: 'Queue' },
    class: { data: 'class_name', title: 'Job Type' },
    problem: { data: 'problem_name', title: 'Problem' },
    user: { data: 'user_name', title: 'User' },
    status: { data: 'status', title: 'Status' },
    submissionId: {
      data: 'submission_id', title: 'Submission', render: function (data, type, row, meta) {
        if (data === null) return ''
        if (type == 'display' || type == 'filter')
          return `<a href="/submissions/${data}"> #${data}</a>`
        return data
      }
    },
    detail: { data: 'detail_html', title: 'Detail' },
    createdAt: { data: 'created_at', title: 'Created At' }
  },
  // --- contest (index, user, problem) ---
  contest: {
    name: { data: 'name' },
    description: { data: 'description' },
    userProb: { data: null, render: renderers.user_prob },
    finalized: { data: 'finalized', render: cafe.dt.render.yes_no_pill(), className: 'text-center' },
    enableToggle: { data: 'id', render: cafe.dt.render.button(null, { element_type: 'switch', action: 'contest#postContestAction', command: 'toggle', checked_data_field: 'enabled' }) },
    start: { data: 'start', render: cafe.dt.render.datetime() },
    stop: { data: 'stop', render: cafe.dt.render.datetime() },
    manageLink: { data: null, render: cafe.dt.render.link(`${cafe.msi('settings')} Manage`, { path: AppRoute.contest, className: 'btn btn-flex btn-outline-primary border-0' }), className: 'align-middle py-1' },
    watchLink: { data: null, render: cafe.dt.render.link(`${cafe.msi('summarize')} Watch`, { path: AppRoute.viewContest, className: 'btn btn-flex btn-outline-success border-0' }), className: 'align-middle py-1' },
    cloneButton: { data: null, render: cafe.dt.render.link(`${cafe.msi('file_copy', 'md-18')} Clone`, { path: AppRoute.cloneContest, className: 'btn btn-sm btn-success', prefetch: false, turboStream: true }), className: 'align-middle py-1' },
    deleteButton: { data: null, render: cafe.dt.render.link(`${cafe.msi('delete', 'md-18')} Destroy`, { path: AppRoute.contest, method: 'delete', confirm: 'Really delete this contest?', className: 'btn btn-sm btn-danger', }), className: 'align-middle py-1' },
    actionButton: {
      data: null, render: function (data, type, row, meta) {

        // only render for display
        if (type != 'display') return ''

        // Generate the standard pill action buttons
        const manage_btn = cafe.dt.render.link(`${cafe.msi('settings')} Manage`, { path: AppRoute.contest, className: 'btn btn-flex btn-outline-primary border-0' })(data, type, row, meta)
        const watch_btn = cafe.dt.render.link(`${cafe.msi('summarize')} Watch`, { path: AppRoute.viewContest, className: 'btn btn-flex btn-outline-success border-0' })(data, type, row, meta)

        // Dropdown actions
        const clone_button = cafe.dt.render.link(`${cafe.msi('file_copy', 'md-18')} Clone`, { path: AppRoute.cloneContest, className: 'dropdown-item d-inline-flex align-items-center', prefetch: false, turboStream: true })(data, type, row, meta)
        const delete_button = cafe.dt.render.link(`${cafe.msi('delete', 'md-18')} Destroy`, { path: AppRoute.contest, className: 'dropdown-item text-danger d-inline-flex align-items-center', method: 'delete', confirm: 'Really delete this contest?' })(data, type, row, meta)

        let dropdown = `<div class="dropdown d-inline-flex align-items-center">` +
          `  <a type="button" class="btn btn-outline-secondary link-flex rounded-1 border-0 p-1" data-bs-toggle="dropdown">` +
          `    <span class="mi">more_horiz</span>` +
          `  </a>` +
          `  <ul class="dropdown-menu dropdown-menu-end border-0 shadow">` +
          `    <li>${clone_button}</li>` +
          `    <li><hr class="dropdown-divider"></li>` +
          `    <li>${delete_button}</li>` +
          `  </ul>` +
          `</div>`

        return `<div class="d-flex gap-1 justify-content-end">${manage_btn} ${watch_btn} ${dropdown}</div>`
      }, className: 'align-middle py-1 pr-2'
    }
  },
  // --- submission ---
  submission: {
    points: { data: 'points', title: 'Raw Points' },
  },
}
