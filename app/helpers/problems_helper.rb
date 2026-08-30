module ProblemsHelper
  # Deep link into the Best Score report for one problem, optionally with a
  # user group pre-picked. The report's filter partials read these params via
  # ReportHelper#report_filter_param, so the page opens with the problem (and
  # group) already selected and the table loaded.
  def problem_score_report_path(problem, group = nil)
    query = { probs: { use: "ids", ids: [problem.id] } }
    query[:users] = { use: "group", group_ids: group.id } if group
    max_score_report_path(query)
  end

  def render_tag(ptag)
    return "<span class='badge text-bg-secondary bg-opacity-100'>#{ptag.name}</span>".html_safe
  end

  def render_star(count)
    count ||= 0
    html = ""
    html += "<span class=\"mi md-18\" style=\"font-variation-settings: 'FILL' 1\">star</span>" * (count/2) if count >= 2
    html += "<span class=\"mi md-18\" > star_half </span>" if count % 2 == 1
    return html.html_safe
  end
end
