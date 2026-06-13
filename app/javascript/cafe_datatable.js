import "datatables"
import "vfs-fonts"
import "pdfmake"
import { escapeHtml } from 'cafe'

function data_tag_unless_null(value,label) {
  return value == null ? "" : `data-${label}="${escapeHtml(value)}"`

}

// This is a DataTable render factory
//
// This function returns a renderer ( function(data,type,row,meta) )
// That renders an element that is supposed to have associated Stimulus action
// It can renders as a link, a button or a bootstrap switch that has 
// data-row-id set to *row['data']* and data-action set to *action*
//
// We can write a Stimulus methods that handles the click event of this element.
// Normal use case is to do some action and/or call some AJAX function to the server.
//
// If we just want to render a link (with Turbo or not), it is better to use dt_link_renderer instead
//
// Here is example usage in a columns: [] configuration of a DataTable
//    {data: 'user_id', 
//     render: cafe.dt.render.button(`[${cafe.msi('person_remove','md-18')} Remove]`, 
//                                     {element_type: 'link', 
//                                        className: 'link-danger', 
//                                        action: 'contest#postUserAction', 
//                                        command: 'remove', 
//                                        confirm: 'Remove user from contest?'})},
function dt_button_renderer(label,{element_type = 'button',
                                   className = 'btn-primary', 
                                   href='#',                       // for 'link' type only
                                   method = null,                  // for 'link' type only
                                   checked_data_field = 'enabled', // for 'switch' type only
                                   action = null,
                                   command = null,
                                   confirm = null,
                                  } = {}) {
  return function(data,type,row,meta) {
    // build data-* attributes
    const dataAction = data_tag_unless_null(action,'action')
    const dataCommand = data_tag_unless_null(command,'command')
    const dataConfirm = data_tag_unless_null(confirm,'form-confirm')
    const dataMethod = data_tag_unless_null(method,'turbo-method') // for link only
    const dataField = data_tag_unless_null(checked_data_field,'field') // for switch only


    if (element_type == 'switch') {
      // as <input type="switch">
      const checked_text = row[checked_data_field] ? "checked" : "";
      return `<div class="d-flex justify-content-center align-items-center">
        <div class="form-check form-switch">
          <input type="checkbox" class="form-check-input" data-row-id="${data}"
          ${dataAction} ${dataCommand} ${dataConfirm} ${checked_text} ${dataField}>
        </div>
        </div>
      `
    } else if (element_type == 'button') {
      // as '<button>'
      return `
        <button class="btn ${className}" data-row-id="${data}" 
        ${dataAction} ${dataCommand} ${dataConfirm}>
        ${label}</button>
      `
    } else if (element_type == 'link') {
      // as '<a>'
      return `
        <a href="${href}" class="${className}" data-row-id="${data}" 
        ${dataAction} ${dataCommand} ${dataConfirm} ${dataMethod}>
        ${label}</a>
      `
    }
  }
}

// Another DataTable render factory. This one render a link as <a href=....>
// It also replace a pattern, default as -123, in the path by the data from row[*replace_field*]
//
// A normal use in a columns options of DataTable is
//
//     {data: null, render: 
//      cafe.dt.render.link(`${cafe.msi('delete','md-18')} Destroy`, {
//        path: '#{user_admin_path(-123)}', 
//        method: 'delete', 
//        confirm: 'Really delete this user?', 
//        className: 'btn btn-sm btn-danger', }), 
//      className: 'align-middle py-1'},
//
// See that the *data* is not used and the renderer just replace -123 with the row['id'], because the default value of *replace_field* is 'id'
// In this case, it just renders user_admin/xxx  where xxx is the row['id'] from the DataTable data
function dt_link_renderer(label,{className = '', path = '#', replace_pattern = '-123', replace_field = 'id', prefetch=false, confirm=null, turbo=false, turboStream=false, method=null} = {}) {
  return function(data,type,row,meta) {
    const dataMethod = data_tag_unless_null(method,'turbo-method')
    let href = path
    if (method || turboStream) turbo = true
    if (replace_field && replace_pattern) {
      href = path.replace(replace_pattern,row[replace_field])
    }
    const dataConfirm = data_tag_unless_null(confirm,'turbo-confirm')
    let link_text = (label === null) ? escapeHtml(data) : label
    return `<a href="${href}" class="${className}" ${dataConfirm} ${dataMethod} data-turbo="${turbo}" data-turbo-prefetch="${prefetch}" data-turbo-stream="${turboStream}"> ${link_text}</a>`
  }
}

// render a yes/no pill
// display a "yes" pill when data is '1', 'true', 1, or true
function dt_yes_no_pill_renderer() {
  return function(data,type,row,meta) {
    if (data == '1' || data == 'true' || data == 1 || data == true)
      if (type == 'display' || type == 'filter')
        return window.CafeUI?.badges?.yes || '<span class="badge text-bg-success">Yes</span>'
      else
        return 'Yes'
    else if (data == '0' || data == 'false' || data == 0 || data == false)
      if (type == 'display' || type == 'filter')
        return window.CafeUI?.badges?.no || '<span class="badge text-bg-secondary">No</span>'
      else
        return 'No'
    return ''
  }
}

function dt_datetime_renderer(format = "Y-MM-DD HH:mm") {
  return function(data,type,row,meta) {
    return moment(data).format(`${format}`)
  }
}

// renderer for json string 
// we assume that "data" is a JSON Array or its string representation
function dt_array_render_factory({format = '${result}', item_format = '${item}', join = ''}) {
  return function(data,type,row,meta) {
    let arr = data

    //check and convert string to array
    if (!Array.isArray(arr)) {
      try {
        arr = JSON.parse(arr)
      } catch { return ''}
    }


    if (type == 'display' || type == 'filter') {
      let item_formatted_arr = arr.map( x => item_format.replace("${item}",escapeHtml(x)))
      return format.replace('${result}', item_formatted_arr.join(join))
    }

    return arr.join(" ")
  }
}

function dt_array_badge_render_factory(className = 'text-bg-secondary') {
  let item_format = `<span class="badge ${className}">\${item}</span>`
  return dt_array_render_factory({item_format: item_format,join: ' ' })
}

const dt = {
  render: {
    button: dt_button_renderer,
    link: dt_link_renderer,
    yes_no_pill: dt_yes_no_pill_renderer,
    datetime: dt_datetime_renderer,
  },
  render_factory: {
    array: dt_array_render_factory,
    badge: dt_array_badge_render_factory,
  },
}

export { dt }
