class SubmissionsController < ApplicationController
  include ProblemAuthorization
  include SubmissionAuthorization

  before_action :check_valid_login

  before_action :set_submission, only: [:show, :show_comments, :download, :compiler_msg, :rejudge, :set_tag, :edit, :evaluations, :archive_viva]
  before_action :set_problem, only: %i[ edit direct_edit_problem rejudge set_tag archive_viva ]
  before_action :set_language, only: %i[ edit direct_edit_problem ]

  before_action :can_view_submission, only: [:show, :show_comments, :download, :edit, :evaluations, :compiler_msg]
  before_action :can_view_problem, only: [ :direct_edit_problem ]
  before_action :can_edit_problem, only: [:rejudge, :set_tag, :archive_viva]

  # GET /submissions
  # GET /submissions.json
  # Show problem selection and user's submission of that problem
  def index
    @problems = @current_user.problems_for_action(:submit)

    if params[:problem_id]==nil
      @problem = nil
      @submissions = nil
    else
      @problem = Problem.find(params[:problem_id]) rescue nil
      if (@problem == nil) || (! @current_user.can_view_problem?(@problem))
        redirect_to list_main_path
        flash[:error] = 'Authorization error: You have no right to view submissions for this problem'
        return
      end


      if GraderConfiguration.contest_mode?
        # when in contest mode, show only submission during this contest
        @submissions = Submission.where(user: @current_user, problem: @problem).where(submitted_at: @current_user.active_contests_range).order(id: :desc)
      else
        @submissions = Submission.where(user: @current_user, problem: @problem).order(id: :desc)
      end


      @sub_details = Hash.new { |h, k| h[k] = {} }
      Comment
        .where(kind: ['llm_assist'], commentable_id: @submissions.ids)
        .group(:commentable_id)
        .select(:commentable_id, "count(comments.id) as llm_count", "sum(comments.cost) as llm_cost")
        .each { |row| @sub_details[row.commentable_id] = { count: row.llm_count, cost: row.llm_cost } }
    end
  end

  # GET /submissions/1
  # GET /submissions/1.json
  def show
    if @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission) and return
    end

    # log the viewing
    user = User.find(session[:user_id])
    SubmissionViewLog.create(user_id: session[:user_id], submission_id: @submission.id) unless user.admin?

    # @evaluations = @submission.evaluations.joins(:testcase).includes(:testcase).order(:group, :num)
    #  .select(:num, :group, :group_name, :weight, :time, :memory, :score, :testcase_id, :result_text, :result)
    @testcases = @submission.problem.live_dataset.testcases.order(:group, :num)
    @evaluations_by_tcid = Evaluation.where(submission: @submission, testcase: @testcases.ids).index_by(&:testcase_id)

    # LLM models for help
    # See config/llm.yml
    @models = Rails.configuration.llm[:provider].keys
  end

  # as Turbo
  # show all comments
  def show_comments
    render turbo_stream: turbo_stream.update(:submission_comments, partial: 'comments', locals: {submission: @submission})
  end

  # on-site new submission on specific problem
  def direct_edit_problem
    if @problem.viva_exam?
      redirect_to viva_start_problem_path(@problem), method: :post and return
    end
    @last_sub = @current_user.last_submission_by_problem(@problem)
    @models = [] # won't allow llm models on the first submission
    @submission_source = nil
    render 'edit'
  end

  # GET /submissions/1/edit
  def edit
    @last_sub = @current_user.last_submission_by_problem(@problem)
    @models = Rails.configuration.llm[:provider].keys
    @submission_source = @submission&.source unless @as_binary
  end

  # as Turbo
  def get_latest_submission_status
    @problem = Problem.find(params[:pid])
    @submission = @current_user.last_submission_by_problem(@problem)
    @delay_value = @submission.nil? ? -1 : (Time.zone.now - @submission.submitted_at).clamp(1, 10).to_i * 1000
    render turbo_stream: [
      turbo_stream.update("latest_status",
                           partial: 'submission_short',
                           locals: {submission: @submission,
                                    refresh_if_not_graded: @delay_value > 0,
                                    show_id: true,
                                    sub_count: @submission&.number,
                                    show_button: false })
    ]
  end
  # Turbo render evaluations as modal popup
  def evaluations
    @testcases = @submission.problem.live_dataset.testcases.order(:group, :num)
    @evaluations_by_tcid = Evaluation.where(submission: @submission, testcase: @testcases.ids).index_by(&:testcase_id)
    render partial: 'msg_modal_show', locals: { do_popup: true, header_msg: 'Evaluation Details', body_msg: render_to_string(partial: 'evaluations', locals: {testcases: @testcases, evaluations_by_tcid: @evaluations_by_tcid}) }
  end

  def download
    if @submission.language.binary? && @submission.binary
      send_data @submission.binary, filename: @submission.download_filename, type: @submission.content_type || 'application/octet-stream', disposition: 'attachment'
      return
    end

    # no binary, send the source
    send_data(@submission.source, {filename: @submission.download_filename, type: 'text/plain'})
  end

  def compiler_msg
    render partial: "msg_modal_show", locals: {do_popup: true, header_msg: "Compiler message for ##{@submission.id}", body_msg: "<pre>#{@submission.compiler_message}</pre>".html_safe}
  end

  # POST /submissions/:id/rejudge
  def rejudge
    if @submission.problem.viva_exam?
      @submission.viva_grade&.destroy
      @submission.update(status: :evaluating, points: nil, grader_comment: nil, graded_at: nil)

      # Optional admin override: re-run with a specific model (e.g., upgrade
      # to gemini-2.5-pro for a stricter grader). Falls back to the service
      # class's DEFAULT_MODEL when not specified.
      job_kwargs = params[:model].present? ? {model: params[:model]} : {}
      Llm::VivaGradeAssistJob.perform_later(@submission, **job_kwargs)

      model_label = params[:model].presence || 'default model'
      @toast = {title: 'Re-grading', body: "Submission ##{@submission.id} grading queued (#{model_label})."}
    else
      # add lower priority job
      @submission.add_judge_job(@submission.problem.live_dataset, -10)
      @toast = {title: 'Rejudge', body: "Submission ##{@submission.id} is added to judge queue."}
    end
    render 'turbo_toast'
  end

  # POST /submissions/:id/archive_viva
  # Admin-only: mark a viva submission as archived so the student can
  # take a fresh viva on the same problem. The original submission
  # (with transcript, grade, costs) is preserved for audit.
  def archive_viva
    unless @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission), alert: 'Not a viva submission.' and return
    end
    unless @submission.status.in?(%w[done grader_error])
      redirect_to viva_submission_path(@submission),
                  alert: "Cannot archive a viva that's still in progress (status: #{@submission.status}). Wait for grading to finish or fail." and return
    end
    @submission.update!(viva_archived_at: Time.current)
    @toast = {title: 'Viva archived',
              body:  "Submission ##{@submission.id} has been archived. The student can now start a new viva on '#{@submission.problem.name}'."}
    render 'turbo_toast'
  end

  def set_tag
    @submission.update(tag: params[:tag])
    redirect_to @submission
  end

protected
  def set_submission
    @submission = Submission.find(params[:id])
  end

  def set_problem
    @problem = @submission.problem if @submission
    @problem = Problem.find(params[:problem_id]) unless @problem
  end

  # need set_problem first
  #
  # The problem's permitted-language set is authoritative: it defines what is
  # submittable. The user's default_language is only a preference used to
  # preselect one of those permitted languages, so it is honored solely when it
  # is itself permitted. This keeps @language (and therefore @as_binary, which
  # drives the upload-vs-editor UI) always inside the permitted set, so the
  # rendered mode can never contradict the language dropdown.
  def set_language
    permitted = @problem.get_permitted_lang_as_ids          # deterministically ordered (by id)
    @language_forced = permitted.count == 1
    default = @current_user.default_language

    @language =
      @submission&.language ||                                  # editing: keep the submission's own language
      (default if default && permitted.include?(default.id)) || # default only when it is permitted
      Language.find_by(id: permitted.first) ||                  # deterministic in-set fallback
      Language.first                                            # guard: stale/empty permitted set

    @as_binary = @language.binary?
  end
end
