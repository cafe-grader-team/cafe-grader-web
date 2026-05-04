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
    @turns = @submission.viva_turns.ordered
    @viva_grade = @submission.viva_grade
    @pending_turn = @submission.viva_turns.where(status: :processing).exists?
    @finished = @submission.status == 'done' || @submission.status == 'grader_error'
  end

  # POST /submissions/:submission_id/viva/turns
  def answer
    unless @current_user == @submission.user || @current_user.admin?
      redirect_to list_main_path, alert: 'Authorization error.' and return
    end

    if @submission.status == 'done' || @submission.status == 'grader_error'
      redirect_to viva_submission_path(@submission), alert: 'This viva session has ended.' and return
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
    @turns = @submission.viva_turns.ordered
    @viva_grade = @submission.viva_grade
    @pending_turn = @submission.viva_turns.where(status: :processing).exists?
    @finished = @submission.status == 'done' || @submission.status == 'grader_error'
    render partial: 'viva_session', locals: {
      submission:   @submission,
      turns:        @turns,
      viva_grade:   @viva_grade,
      pending_turn: @pending_turn,
      finished:     @finished
    }
  end

  private

  def set_problem
    @problem = Problem.find(params[:id] || params[:problem_id])
  end

  def set_submission
    @submission = Submission.find(params[:submission_id] || params[:id])
  end
end
