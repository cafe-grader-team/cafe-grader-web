module ProblemsHelper
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
