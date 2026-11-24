module SubmissionsHelper
  # The price sentence of the AI-help confirm dialog (Markdown source). `cost`
  # is what THIS requester would be charged — Llm::CommentAssist.assist_cost_for:
  # 0 for an admin asking on a student's behalf, or when the site price is 0.
  def llm_assist_price_sentence(cost)
    if cost.to_i.zero?
      'This request does not reduce the __full score__ for this problem.'
    else
      "Requesting assistance will reduce the __full score__ for this problem by #{cost} points. " \
      'If your final score for this problem does not exceed the __reduced full score__, you will receive that score. ' \
      'If your score exceeds the __reduced full score__, it will be capped at the __reduced full score__.'
    end
  end

  # "test-drive" badge for staff surfaces (viva session page, viva alerts,
  # stuck turns). An author's trial run of a viva — graded like a real
  # session but excluded from reports, cost figures and start limits.
  # Renders nothing for a real submission.
  def submission_test_drive_badge(submission)
    return unless submission.test_drive?
    content_tag :span, 'test-drive', class: 'badge text-bg-info ms-1',
                title: 'Author test-drive — excluded from reports, cost figures and start limits'
  end

  # --- grade-history table (viva_sessions/_grade_history) ---

  # One badge per run outcome: the current run, or why a run is not current.
  def viva_grade_outcome_badge(run)
    label, klass, title =
      if run.current?
        ['current', 'text-bg-success', 'This run is the current grade: its total is the submission score']
      else
        case run.superseded_reason
        when 'replaced' then ['replaced', 'text-bg-secondary', "Replaced by run ##{run.superseded_by_id}"]
        when 'lower'    then ['lower',    'text-bg-warning',   'Not adopted: scored lower than the current grade (keep the higher grade)']
        when 'error'    then ['error',    'text-bg-danger',    run.error.presence || 'The grader produced no grade']
        when 'reverted' then ['reverted', 'text-bg-secondary', "Displaced when run ##{run.superseded_by_id} was made current"]
        else                 ['not adopted', 'text-bg-secondary', 'Written but not adopted (still deciding, or interrupted)']
        end
      end
    content_tag :span, label, class: "badge #{klass}", title: title
  end

  # Who asked for the run: an admin's login, the batch id, or "auto" for the
  # grading that follows the end of an interview.
  def viva_grade_requester_label(run)
    if run.requested_by then run.requested_by.login
    elsif run.batch_id.present? then "batch #{run.batch_id}"
    else 'auto'
    end
  end

  # Tooltip for the Rubric column: does the run's rubric_version match the
  # problem's current rubric context (nil when the problem has no briefing)?
  def viva_grade_rubric_title(run, current_rubric)
    return 'Legacy run: rubric version not recorded' if run.rubric_version.blank?
    return 'Rubric version at grading time' if current_rubric.nil?
    run.rubric_version == current_rubric ? "Graded under the problem's current rubric" : 'Graded under an earlier rubric (stale)'
  end
end
