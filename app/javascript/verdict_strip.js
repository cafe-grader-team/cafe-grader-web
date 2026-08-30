// Client-side twin of GraderCommentHelper#grader_comment_strip, for tables
// whose cells DataTables renders from JSON (report/submission). Same markup
// and classes; the letter → result/word table comes from the server
// (GraderCommentHelper#verdict_strip_config_json) so it is defined once.
//
//   render: (data, type) => type === 'display' ? cafe.verdictStrip(data, VERDICT_STRIP) : data

const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))

export function verdictStrip(comment, config) {
  comment = comment == null ? '' : String(comment)
  const codes = config.codes
  const cls = '[' + Object.keys(codes).join('').replace(/[-\]\\^]/g, '\\$&') + ']'
  const valid = new RegExp(`^(?:${cls}+|\\[${cls}+\\])+$`)
  if (!valid.test(comment)) {
    return `<span class="grader-comment grader-comment-capped"> [${esc(comment)}]</span>`
  }
  const total = comment.replace(/[\[\]]/g, '').length
  const groups = (comment.match(/\[/g) || []).length
  let index = 0, groupIndex = 0
  const tiles = run => [...run].map(code => {
    index += 1
    const { result, word } = codes[code]
    return `<span class="verdict-tile verdict-${result}" title="Test ${index} of ${total}: ${esc(word)}">${code}</span>`
  }).join('')
  const token = new RegExp(`\\[(${cls}+)\\]|(${cls}+)`, 'g')
  let html = '', m
  while ((m = token.exec(comment)) !== null) {
    if (m[1] !== undefined) {
      groupIndex += 1
      const passed = (m[1].match(/P/g) || []).length
      const title = `Group ${groupIndex} of ${groups}: ${passed}/${m[1].length} passed. ${config.group_hint}`
      html += `<span class="verdict-group" title="${esc(title)}">${tiles(m[1])}</span>`
    } else {
      html += `<span class="verdict-run">${tiles(m[2])}</span>`
    }
  }
  return `<span class="verdict-strip" data-comment="${esc(comment)}">${html}</span>`
}
