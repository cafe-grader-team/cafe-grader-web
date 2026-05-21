module MainHelper
  # The /main/list page is hot — called frequently by many users across
  # a large problem set — so this helper deliberately AVOIDS calling
  # User#can_view_problem_pdf? (which would N+1 across problems_for_action
  # joins for every row). The controller-side gate
  # (ProblemsController#download_by_type) is the security boundary; this
  # is just the visibility hint. We check the cheap column-level flag
  # on the already-loaded problem.
  def link_to_description_if_any(name, problem, **options)
    return ''.html_safe unless problem.pdf_visible_to_student?
    if !problem.url.blank?
      return link_to name, problem.url, **options
    elsif problem.statement.attached?
      return link_to name, download_by_type_problem_path(problem, 'statement'), target: '_blank', data: {turbo: false}, **options
    else
      return ''
    end
  end
end
