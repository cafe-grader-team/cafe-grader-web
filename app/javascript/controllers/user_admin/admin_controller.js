import BaseController from "controllers/user_admin/base_controller"

export default class extends BaseController {

  connect(event) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    this.element.querySelectorAll('table.role-table').forEach((table) => {
      $(table).DataTable({
        processing: true,
        rowId: 'id',
        destroy: true,
        pageLength: 50,
        ajax: {
          url: table.dataset.queryUrl,
          type: 'POST',
          headers: csrfToken ? { 'X-CSRF-Token': csrfToken } : {},
          dataSrc: (json) => json.data,
        },
        layout: {
          topStart: 'info',
          topEnd: 'search',
        },
        columns: [
          {data: 'login'},
          {data: 'full_name'},
          {data: 'id', className: 'text-end',
           render: cafe.dt.render.button(`[${cafe.msi('remove_moderator')} Revoke]`,
             {element_type: 'link',
              action: 'user-admin--admin#postUserAction',
              command: 'revoke',
              className: 'link-danger'})},
        ],
        columnDefs: [{orderable: false, targets: [2]}],
      })
    })
  }

  // Click handler for the Grant button: stamp command='grant' on the enclosing form.
  setGrantCommand(event) {
    const form = event.target.closest('form.role-form')
    if (form) form.querySelector('.role-command').value = 'grant'
  }

  // Click handler for Revoke link in a table: find the form for that table's role,
  // stamp command='revoke' and the user id, then submit.
  postUserAction(event) {
    event.preventDefault()
    const table = event.target.closest('table.role-table')
    const role = table?.dataset.role
    const form = this._formForRole(role)
    if (!form) return
    form.querySelector('.role-command').value = event.target.dataset.command
    form.querySelector('select[name="id"]').value = event.target.dataset.rowId
    this.confirmSubmit(form, event)
  }

  _formForRole(role) {
    return Array.from(this.element.querySelectorAll('form.role-form'))
                .find((f) => f.querySelector('input[name="role"]')?.value === role)
  }

  afterUserAction(event) {
    const form = event.target
    const tableId = form.dataset.roleTable
    if (tableId) {
      $(`#${tableId}`).DataTable().ajax.reload()
      const select = form.querySelector('select[name="id"]')
      $(select).val(null).trigger('change')
    }
  }
}
