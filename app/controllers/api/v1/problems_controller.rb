class Api::V1::ProblemsController < Api::V1::BaseController
  before_action :set_problem, only: [:show, :description, :file, :data_files, :testcases]

  # GET /api/v1/problems
  def index
    problems = current_user.problems_for_action(:submit, respect_admin: false)
      .includes(:public_tags)
      .with_attached_statement
      .with_attached_attachment
      .default_order

    submissions = Submission.where(user: current_user, problem: problems)
    prob_stats = build_problem_stats(submissions)

    render json: problems.map { |p| problem_list_json(p, prob_stats[p.id]) }
  end

  # GET /api/v1/problems/:id
  def show
    submissions = Submission.where(user: current_user, problem: @problem)
    stat = build_problem_stats(submissions)[@problem.id] || {}
    last = stat[:last]

    render json: {
      id: @problem.id,
      name: @problem.name,
      full_name: @problem.full_name,
      full_score: @problem.full_score,
      difficulty: @problem.difficulty,
      tags: @problem.public_tags.pluck(:name),
      submission_count: stat[:count] || 0,
      best_score: stat[:best_score],
      last_score: last&.points,
      last_result: last&.grader_comment,
      last_submission_time: last&.submitted_at,
      has_testcase: @problem.can_view_testcase,
      has_attachment: @problem.attachment.attached?,
      permitted_languages: permitted_languages_for(@problem),
      submission_ids: submissions.order(submitted_at: :desc).pluck(:id)
    }
  end

  # GET /api/v1/problems/:id/description
  def description
    render json: {
      markdown: @problem.markdown?,
      description: @problem.description
    }
  end

  # GET /api/v1/problems/:id/files/:type
  def file
    # The dataset is only needed for checker/manager (they hang off the
    # live dataset). PDF and attachment live on Problem directly, so
    # demanding a live_dataset here used to lock viva problems (which
    # have no dataset by design) out of the PDF endpoint entirely.
    # Resolved on demand inside the branches that need it.

    case params[:type]
    when "pdf"
      # PDF statement is hidden from students for problem modes where
      # the PDF is staff-only (viva). Mirrors the web equivalent in
      # ProblemsController#download_by_type.
      unless current_user.can_view_problem_pdf?(@problem)
        render json: {error: "PDF statement not available for this problem"}, status: :forbidden and return
      end
      if @problem.statement.attached?
        send_data @problem.statement.download,
          type: @problem.statement.content_type,
          filename: @problem.statement.filename.to_s,
          disposition: "inline"
      elsif @problem.generated_statement.attached?
        send_data @problem.generated_statement.download,
          type: "application/pdf",
          filename: "#{@problem.name}.pdf",
          disposition: "inline"
      else
        render_not_found("PDF statement")
      end
    when "attachment"
      if @problem.attachment.attached?
        send_data @problem.attachment.download,
          type: @problem.attachment.content_type,
          filename: @problem.attachment.filename.to_s
      else
        render_not_found("Attachment")
      end
    when "checker"
      return unless authorize_edit!
      dataset = @problem.live_dataset
      return render_not_found("Dataset") unless dataset
      if dataset.checker.attached?
        send_data dataset.checker.download,
          type: "application/octet-stream",
          filename: dataset.checker.filename.to_s
      else
        render_not_found("Checker")
      end
    when "manager"
      dataset = @problem.live_dataset
      return render_not_found("Dataset") unless dataset
      managers = dataset.managers
      if managers.attached?
        render json: managers.map { |m|
          { id: m.id, filename: m.filename.to_s }
        }
      else
        render json: []
      end
    else
      render json: { error: "Unknown file type: #{params[:type]}" }, status: :bad_request
    end
  end

  # GET /api/v1/problems/:id/data_files
  def data_files
    return unless authorize_edit!
    dataset = @problem.live_dataset
    unless dataset
      render_not_found("Dataset") and return
    end

    if dataset.data_files.attached?
      render json: dataset.data_files.map { |f|
        { id: f.id, filename: f.filename.to_s, byte_size: f.byte_size }
      }
    else
      render json: []
    end
  end

  # GET /api/v1/problems/:id/testcases
  def testcases
    unless current_user.can_view_testcase?(@problem)
      render json: { error: "You are not allowed to view testcases for this problem" }, status: :forbidden and return
    end

    dataset = @problem.live_dataset
    tcs = dataset.testcases.display_order

    render json: tcs.map { |tc|
      {
        id: tc.id,
        num: tc.num,
        group: tc.group,
        group_name: tc.group_name,
        weight: tc.weight
      }
    }
  end

  private

  def set_problem
    @problem = current_user.problems_for_action(:submit).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Problem")
  end

  def authorize_edit!
    return true if current_user.can_edit_problem?(@problem)
    render json: { error: "Forbidden" }, status: :forbidden
    false
  end

  def build_problem_stats(submissions)
    stats = Hash.new { |h, k| h[k] = {} }

    last_sub_ids = submissions.group(:problem_id).pluck("max(id)")
    Submission.where(id: last_sub_ids).each do |sub|
      stats[sub.problem_id][:count] = sub.number
      stats[sub.problem_id][:last] = sub
    end

    submissions.group(:problem_id).pluck("problem_id", "max(points)").each do |pid, max|
      stats[pid][:best_score] = max
    end

    stats
  end

  def problem_list_json(problem, stat)
    stat ||= {}
    last = stat[:last]
    {
      id: problem.id,
      name: problem.name,
      full_name: problem.full_name,
      difficulty: problem.difficulty,
      tags: problem.public_tags.pluck(:name),
      submission_count: stat[:count] || 0,
      best_score: stat[:best_score],
      last_score: last&.points,
      last_result: last&.grader_comment,
      last_submission_time: last&.submitted_at,
      has_testcase: problem.can_view_testcase,
      has_attachment: problem.attachment.attached?,
      permitted_languages: permitted_languages_for(problem)
    }
  end

  def permitted_languages_for(problem)
    ids = problem.get_permitted_lang_as_ids(when_blank: nil)
    return nil if ids.nil?  # nil means all languages allowed
    Language.where(id: ids).map { |l| { id: l.id, name: l.name, ext: l.ext } }
  end
end
