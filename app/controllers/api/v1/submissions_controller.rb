class Api::V1::SubmissionsController < Api::V1::BaseController
  before_action :set_problem, only: [:index, :create]

  # GET /api/v1/problems/:problem_id/submissions
  def index
    submissions = Submission.where(user: current_user, problem: @problem)
      .order(submitted_at: :desc)

    render json: submissions.map { |s| submission_brief_json(s) }
  end

  # GET /api/v1/submissions/:id
  def show
    submission = Submission.includes(:evaluations).find(params[:id])

    unless current_user.can_view_submission?(submission)
      render json: { error: "Forbidden" }, status: :forbidden and return
    end

    render json: {
      id: submission.id,
      problem_id: submission.problem_id,
      problem_name: submission.problem.name,
      user_id: submission.user_id,
      language: submission.language.name,
      source: (submission.source if submission.user == current_user || current_user.admin?),
      source_filename: submission.source_filename,
      submitted_at: submission.submitted_at,
      # points is DECIMAL (BigDecimal) — Rails JSON-encodes it as a string; cast to float
      points: submission.points&.to_f,
      status: submission.status,
      grader_comment: submission.grader_comment,
      compiler_message: submission.compiler_message,
      max_runtime: submission.max_runtime,
      peak_memory: submission.peak_memory,
      number: submission.number,
      evaluations: submission.evaluations.map { |e|
        {
          testcase_id: e.testcase_id,
          result: e.result,
          score: e.score&.to_f,
          time: e.time,
          memory: e.memory
        }
      }
    }
  rescue ActiveRecord::RecordNotFound
    render_not_found("Submission")
  end

  # POST /api/v1/problems/:problem_id/submissions
  def create
    unless current_user.problems_for_action(:submit).where(id: @problem).any?
      render json: { error: "You are not allowed to submit to this problem" }, status: :forbidden and return
    end

    language = Language.find_by(id: params[:language_id])
    language ||= Language.find_by_extension(params[:filename]&.split(".")&.last)
    permitted = @problem.get_permitted_lang_as_ids
    language = Language.find(permitted[0]) if permitted.count == 1
    language ||= Language.find_by(name: "cpp")

    # Validate language is permitted for this problem
    if language && permitted.any? && !permitted.include?(language.id)
      render json: {
        error: "Language '#{language.name}' is not permitted for this problem",
        permitted_languages: Language.where(id: permitted).pluck(:id, :name).map { |id, name| { id: id, name: name } }
      }, status: :unprocessable_entity and return
    end

    submission = Submission.new(
      user: current_user,
      problem: @problem,
      language: language,
      submitted_at: Time.zone.now,
      ip_address: request.remote_ip
    )

    if params[:source].present?
      submission.source = params[:source]
      submission.source_filename = params[:filename] || "submit.#{language.ext}"
    elsif params[:file].present?
      if language.binary?
        submission.binary = params[:file].read
        submission.content_type = params[:file].content_type
        submission.source_filename = params[:file].original_filename
      else
        submission.source = params[:file].read.force_encoding("UTF-8")
          .encode("UTF-8", invalid: :replace, replace: "")
        submission.source_filename = params[:file].original_filename
      end
    else
      render json: { error: "No source code provided" }, status: :unprocessable_entity and return
    end

    if submission.save
      submission.add_judge_job
      render json: { id: submission.id, number: submission.number, status: submission.status }, status: :created
    else
      render json: { errors: submission.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_problem
    @problem = Problem.find(params[:problem_id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Problem")
  end

  def submission_brief_json(s)
    {
      id: s.id,
      number: s.number,
      language: s.language.name,
      submitted_at: s.submitted_at,
      points: s.points&.to_f,
      status: s.status,
      grader_comment: s.grader_comment
    }
  end
end
