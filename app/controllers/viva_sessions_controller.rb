class VivaSessionsController < ApplicationController
  before_action :check_valid_login
  before_action :set_problem, only: %i[start]
  before_action :set_submission, only: %i[show answer refresh]

  VIVA_LANGUAGE_NAME = 'viva'.freeze

  # POST /problems/:problem_id/viva/start
  def start
    unless @problem.viva_exam?
      redirect_to list_main_path, alert: 'This problem is not a viva exam.' and return
    end

    unless @current_user.problems_for_action(:submit).where(id: @problem.id).any?
      redirect_to list_main_path, alert: 'Authorization error: you have no right to start a viva for this problem.' and return
    end

    viva_lang = Language.find_by(name: VIVA_LANGUAGE_NAME)
    unless viva_lang
      redirect_to list_main_path, alert: 'Viva language is not seeded. Run Language.seed.' and return
    end

    setup_errors = @problem.viva_setup_errors
    if setup_errors.any?
      redirect_to list_main_path,
                  alert: "Cannot start viva for '#{@problem.name}' — problem setup is incomplete: #{setup_errors.join('; ')}"
      return
    end

    # Defensive: if the user already has an active (non-archived) viva
    # submission for this problem, the Start Viva button shouldn't be
    # visible — but a stale browser tab or a direct curl POST could land
    # here anyway. Refuse with a clear flash.
    if @problem.submissions.where(user: @current_user, viva_archived_at: nil).exists?
      redirect_to list_main_path,
                  alert: "You already have an active viva session for '#{@problem.name}'. An admin can archive it from the viva page if you need to retake."
      return
    end

    submission = nil
    placeholder = nil
    Submission.transaction do
      submission = Submission.create!(
        user:     @current_user,
        problem:  @problem,
        language: viva_lang,
        source:   nil,
        source_filename: nil,
        status:   :submitted,
        submitted_at: Time.zone.now,
        ip_address: request.remote_ip
      )

      submission.viva_turns.create!(role: :system, status: :ok, content: '(interview start)')
      placeholder = submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    end

    Llm::VivaTurnAssistJob.perform_later(submission, turn: placeholder)
    redirect_to viva_submission_path(submission)
  end

  # GET /submissions/:submission_id/viva
  def show
    load_viva_state
  end

  # POST /submissions/:submission_id/viva/turns
  def answer
    unless @current_user == @submission.user || @current_user.admin?
      redirect_to list_main_path, alert: 'Authorization error.' and return
    end

    case @submission.status.to_s
    when 'done', 'grader_error'
      redirect_to viva_submission_path(@submission), alert: 'This viva session has ended.' and return
    when 'evaluating'
      # Interview already ended (LLM emitted [[VIVA_DONE]]); a grade job is
      # in flight. Accepting a new student turn here would race with the
      # grader and corrupt the transcript, so refuse.
      redirect_to viva_submission_path(@submission), alert: 'Interview ended — grading in progress.' and return
    end

    if @submission.viva_turns.where(status: :processing).exists?
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to viva_submission_path(@submission), alert: 'Waiting for the previous response.' }
      end
      return
    end

    student_content = params[:content].to_s.strip
    if student_content.blank?
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to viva_submission_path(@submission), alert: 'Answer cannot be empty.' }
      end
      return
    end

    placeholder = nil
    Submission.transaction do
      @submission.viva_turns.create!(role: :student, status: :ok, content: student_content)
      placeholder = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    end

    Llm::VivaTurnAssistJob.perform_later(@submission, turn: placeholder)

    respond_to do |format|
      format.turbo_stream { redirect_to viva_submission_path(@submission) }
      format.html { redirect_to viva_submission_path(@submission) }
    end
  end

  # GET /submissions/:submission_id/viva/refresh
  def refresh
    load_viva_state
    render partial: 'viva_session', locals: {
      submission:   @submission,
      turns:        @turns,
      viva_grade:   @viva_grade,
      pending_turn: @pending_turn,
      finished:     @finished
    }
  end

  private

  # Shared by #show and #refresh. The "pending" flag drives both polling
  # (keep refreshing while the backend is still doing work) and the
  # answer-form's disabled state. It's true while a turn is being
  # generated *or* the grader is running, so the UI keeps polling
  # until the grade lands or fails.
  #
  # The "finished" flag drives whether the answer form is shown at all
  # — once we're in :evaluating, :done, or :grader_error, the student
  # can't submit more answers, and the view falls through to either
  # "Grading in progress…", the grade card, or a "Grader error" alert.
  def load_viva_state
    @turns        = @submission.viva_turns.ordered
    @viva_grade   = @submission.viva_grade
    @pending_turn = @submission.viva_turns.where(status: :processing).exists? ||
                    @submission.status == 'evaluating'
    @finished     = %w[done grader_error evaluating].include?(@submission.status.to_s)
  end

  def set_problem
    @problem = Problem.find(params[:id] || params[:problem_id])
  end

  def set_submission
    @submission = Submission.find(params[:submission_id] || params[:id])
  end
end
