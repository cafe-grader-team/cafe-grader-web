class VivaSessionsController < ApplicationController
  before_action :check_valid_login
  before_action :set_problem, only: %i[start test_drive]
  before_action :set_submission, only: %i[show answer refresh retry_turn restart finish]
  # #answer/#retry_turn/#restart already enforce their own (stricter, owner-
  # or-admin) checks below — this gate is only for the read paths, which
  # previously had no authorization beyond being logged in at all. Reuses
  # the platform's existing submission-view predicate rather than
  # duplicating its admin/reporter/owner/config logic here.
  before_action :authorize_viva_view, only: %i[show refresh]

  VIVA_LANGUAGE_NAME = Language::VIVA_NAME

  # #answer and #retry_turn on an archived session.
  CLOSED_SESSION_ALERT = 'This session has been closed. Start a new one from the problem list if you have a start left.'.freeze

  # The start limit, the contest-only rule and Restart's guard live in one
  # place, Viva::StartPolicy (design 2026-10-07); #start, #restart and the
  # session page all ask it.

  # POST /problems/:problem_id/viva/start
  def start
    unless @problem.viva_exam?
      redirect_to list_main_path, alert: 'This problem is not a viva exam.' and return
    end

    # Same gate as code problems (User#can_submit_to_problem?): members need a
    # fully-live problem; a group's editor may also test-start a draft/hidden
    # viva in their own groups. Viva authorization matches normal problems.
    unless @current_user.can_submit_to_problem?(@problem)
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
    if @problem.submissions.regular.where(user: @current_user, viva_archived_at: nil).exists?
      redirect_to list_main_path,
                  alert: "You already have an active viva session for '#{@problem.name}'. Open it from the problem list, or ask staff to allow another attempt."
      return
    end

    # Start limit and contest-only rule (Viva::StartPolicy; admins exempt).
    # For a contest-only viva in contest mode, can_submit_to_problem? above
    # already proved the problem is visible through an active contest the
    # student is enrolled in, so the global contest-mode flag is enough here.
    if (refusal = Viva::StartPolicy.new(@problem, @current_user).refusal)
      redirect_to list_main_path, alert: refusal and return
    end

    submission = create_viva_session!(@problem, viva_lang)
    redirect_to viva_submission_path(submission)
  end

  # POST /problems/:problem_id/viva/test_drive
  #
  # Author's test-drive (design D7; spec 2026-09-23-viva-test-drive-design):
  # an editor of the problem's group, or an admin, sits the viva in a session
  # flagged submissions.test_drive. The interview and grading run exactly as
  # for a student; the flag keeps the session out of every report, score,
  # cost figure and quota (Submission.regular excludes it) and out of the
  # three student gates #start applies — the daily start limit, the
  # contest-only rule, and the one-active-session guard, which here looks at
  # test-drives only: a second click while one is open just reopens it.
  # The setup check stays: a viva with no briefing cannot assemble a prompt.
  def test_drive
    unless @current_user.can_edit_problem?(@problem)
      redirect_to list_main_path, alert: 'Authorization error: only editors of this problem may test-drive it.' and return
    end
    unless @problem.viva_exam?
      redirect_to edit_problem_path(@problem), alert: 'This problem is not a viva exam.' and return
    end
    viva_lang = Language.find_by(name: VIVA_LANGUAGE_NAME)
    unless viva_lang
      redirect_to edit_problem_path(@problem), alert: 'Viva language is not seeded. Run Language.seed.' and return
    end
    setup_errors = @problem.viva_setup_errors
    if setup_errors.any?
      redirect_to edit_problem_path(@problem),
                  alert: "Cannot test-drive '#{@problem.name}' — problem setup is incomplete: #{setup_errors.join('; ')}"
      return
    end

    # "Open" = interview or grading still in progress. A graded test-drive stays
    # in the list as a record but does not stand in the way of a fresh run.
    open_drive = @problem.submissions.test_drives
                         .where(user: @current_user, viva_archived_at: nil, status: %i[submitted evaluating])
                         .order(:id).last
    if open_drive
      redirect_to viva_submission_path(open_drive),
                  notice: 'You already have an open test-drive on this problem — continuing it.'
      return
    end

    submission = create_viva_session!(@problem, viva_lang, test_drive: true)
    redirect_to viva_submission_path(submission),
                notice: 'Test-drive started — this session is excluded from reports, cost figures and start limits.'
  end

  # GET /submissions/:submission_id/viva
  def show
    load_viva_state

    # Retake-policy visibility (Viva::StartPolicy — the rule #start and
    # #restart apply): starts left today for the session's owner, and whether
    # the owner's Restart button is offered at all. Only the Viva Info card
    # reads these, so the 3 s #refresh (the transcript partial) skips them.
    policy = Viva::StartPolicy.new(@submission.problem, @submission.user)
    @daily_start_limit = policy.limit || Viva::StartPolicy.daily_limit_for(@submission.problem)
    @starts_left       = policy.starts_left || @daily_start_limit
    @restart_allowed   = policy.restart_allowed?(@submission)
  end

  # POST /submissions/:submission_id/viva/turns
  def answer
    # Only the submission owner may post answers. Admins / other privileged
    # users can still VIEW (#show, #refresh stay open), but posting on
    # behalf of someone else corrupts transcript ownership — refuse.
    unless @current_user == @submission.user
      redirect_to list_main_path, alert: "You cannot post to another user's viva session." and return
    end

    student_content = params[:content].to_s.strip

    # Check-and-transition under a row lock. Two POSTs that arrive together —
    # a double-click on Send, a second tab, a browser retry — used to both
    # read the same state and both act on it: at the hard cap that meant two
    # closing turns and two grade jobs for one interview; below it, two
    # student turns and two assist jobs. The second request now waits for
    # the first to commit, re-reads the row (lock! reloads) and is refused
    # like any other late POST. Jobs are enqueued after the block commits so
    # a worker never sees pre-commit state.
    placeholder = nil
    outcome = @submission.with_lock do
      # A closed (archived) session takes no more answers — Restart, Allow
      # another attempt or Finish open vivas closed it (design 2026-10-07, A4).
      next :archived if @submission.viva_archived_at.present?
      case @submission.status.to_s
      when 'done', 'grader_error' then next :ended
      when 'evaluating'           then next :grading
      end
      next :busy  if @submission.viva_turns.where(status: :processing).exists?
      next :blank if student_content.blank?

      # Hard turn cap (design D8): at the limit we force-finish instead of
      # accepting another answer — the soft cap should normally end the
      # interview well before this fires.
      if @submission.viva_turns.where(role: :student).count >= @submission.problem.viva_hard_cap
        force_finish!('(turn limit reached — the interview ends here and grading begins)')
        next :capped
      end

      @submission.viva_turns.create!(role: :student, status: :ok, content: student_content)
      placeholder = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
      :accepted
    end

    case outcome
    when :archived
      redirect_to viva_submission_path(@submission), alert: CLOSED_SESSION_ALERT
    when :ended
      redirect_to viva_submission_path(@submission), alert: 'This viva session has ended.'
    when :grading
      # Interview already ended (LLM emitted [[VIVA_DONE]]); a grade job is
      # in flight. Accepting a new student turn here would race with the
      # grader and corrupt the transcript, so refuse.
      redirect_to viva_submission_path(@submission), alert: 'Interview ended — grading in progress.'
    when :busy
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to viva_submission_path(@submission), alert: 'Waiting for the previous response.' }
      end
    when :blank
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to viva_submission_path(@submission), alert: 'Answer cannot be empty.' }
      end
    when :capped
      Llm::VivaGradeAssistJob.perform_later(@submission)
      redirect_to viva_submission_path(@submission), notice: 'Turn limit reached — grading has started.'
    when :accepted
      Llm::VivaTurnAssistJob.perform_later(@submission, turn: placeholder)
      respond_to do |format|
        format.turbo_stream { redirect_to viva_submission_path(@submission) }
        format.html { redirect_to viva_submission_path(@submission) }
      end
    end
  end

  # POST /submissions/:submission_id/viva/turns/:turn_id/retry
  #
  # Re-runs the LLM call for a failed assistant turn. Resets the turn
  # back to :processing (clearing content + LLM metadata) and enqueues
  # a fresh VivaTurnAssistJob.
  #
  # Allowed for owner OR admin — unlike #answer (which strictly forbids
  # admin posting on behalf of the student), retry doesn't add new
  # student content; it just asks the LLM to take another shot at the
  # student's previous answer. Admins routinely rescue stuck sessions.
  #
  # Only :error turns can be retried; in-flight :processing turns are
  # left alone (they may still complete normally, and the
  # VivaTurn.fail_stale! sweeper will eventually mark genuinely stuck
  # ones as :error so they become retryable).
  def retry_turn
    turn = @submission.viva_turns.find(params[:turn_id])

    unless @current_user == @submission.user || @current_user.admin?
      redirect_to viva_submission_path(@submission),
                  alert: 'You are not allowed to retry this turn.' and return
    end

    unless turn.role == 'assistant'
      redirect_to viva_submission_path(@submission),
                  alert: 'Only interviewer turns can be retried.' and return
    end

    unless turn.status == 'error'
      redirect_to viva_submission_path(@submission),
                  alert: 'Only failed turns can be retried.' and return
    end

    case @submission.status.to_s
    when 'done', 'grader_error', 'evaluating'
      redirect_to viva_submission_path(@submission),
                  alert: 'This viva session has already ended.' and return
    end

    # A closed (archived) session is not revived by a retry, the owner's or
    # an admin's (design 2026-10-07, A4).
    if @submission.viva_archived_at.present?
      redirect_to viva_submission_path(@submission), alert: CLOSED_SESSION_ALERT and return
    end

    turn.update!(
      status:           :processing,
      content:          nil,
      llm_response_raw: nil,
      cost:             nil,
      token_count_in:   nil,
      token_count_out:  nil,
      llm_model:        nil,
      alerted:          false
    )

    Llm::VivaTurnAssistJob.perform_later(@submission, turn: turn)

    redirect_to viva_submission_path(@submission),
                notice: 'Retrying the interviewer response...'
  end

  # POST /submissions/:submission_id/viva/restart
  #
  # Self-service retake (design 2026-07-21, Phase A): every viva is
  # practice, so the owner can always archive their own session so the
  # Start Viva button reappears — subject to the daily start guard in
  # #start on the *next* attempt, and offered only when that next attempt is
  # possible (Viva::StartPolicy#restart_allowed?). Staff can still allow
  # another attempt (SubmissionsController#allow_viva_retake).
  def restart
    unless @current_user == @submission.user
      redirect_to viva_submission_path(@submission), alert: 'Only the owner can restart their viva.' and return
    end
    # Non-viva submissions must never be archivable this way: archiving
    # hides a submission from main_controller's canonical max(id) pick — a
    # grade-manipulation vector if it could be triggered on an ordinary
    # coding submission.
    unless @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission), alert: 'Restart is only available for viva exam problems.' and return
    end

    # Restart only when the student could start again afterwards (design
    # 2026-10-07, A3): archiving their only counted session mid-interview used
    # to leave them with no session, no grade and no way back.
    policy = Viva::StartPolicy.new(@submission.problem, @current_user)
    unless policy.restart_allowed?(@submission)
      redirect_to viva_submission_path(@submission),
                  alert: "Restart is not available — you could not start a new session afterwards. #{policy.refusal}" and return
    end

    # Same row lock as #answer / #finish. Two concurrent Restart clicks used
    # to both pass the not-archived check — harmless while restart only
    # archived (idempotent), but a test-drive restart now CREATES a fresh
    # session, so the second click must be refused, not doubled. The fresh
    # session is created after the lock block has committed.
    outcome = @submission.with_lock do
      next :archived if @submission.viva_archived_at.present?
      next :busy     if @submission.viva_turns.where(status: :processing).exists?
      @submission.update!(viva_archived_at: Time.zone.now)
      :restarted
    end

    case outcome
    when :archived
      redirect_to viva_submission_path(@submission), alert: 'This viva session has already been archived.'
    when :busy
      redirect_to viva_submission_path(@submission), alert: 'Wait for the current response to finish first.'
    when :restarted
      problem = @submission.problem
      if @submission.test_drive?
        # Test-drives restart in place: archive, then open a fresh test-drive
        # at once — no limit, no detour through the problem list. The setup
        # check runs again: the briefing may have been blanked since the first
        # start, and a fresh session with no prompt could only error.
        setup_errors = problem.viva_setup_errors
        if setup_errors.any?
          redirect_to edit_problem_path(problem),
                      alert: "Test-drive archived, but a fresh one cannot start — problem setup is incomplete: #{setup_errors.join('; ')}"
        else
          fresh = create_viva_session!(problem, Language.find_by!(name: VIVA_LANGUAGE_NAME), test_drive: true)
          redirect_to viva_submission_path(fresh), notice: 'Test-drive restarted — the previous session is archived.'
        end
      elsif problem.viva_daily_limit == 0
        redirect_to list_main_path, notice: 'Viva archived — start a fresh one from the problem list (only available during a contest).'
      else
        redirect_to list_main_path, notice: "Viva archived — start a fresh one from the problem list (limit #{Viva::StartPolicy.daily_limit_for(problem)} per day)."
      end
    end
  end

  # POST /submissions/:submission_id/viva/finish
  #
  # Student-initiated end (practice only): finalize the interview now and
  # grade what the transcript shows. Mirrors the hard-cap path in #answer —
  # same system turn + :evaluating + grade job with no model: argument (the
  # grade service's default decides, rev 2011). Rubric criteria never
  # reached score zero, so the UI confirm warns before committing. Not
  # offered on contest-only vivas (viva_daily_limit == 0): ending early to
  # lock in credit before deeper probing is an exam-gaming vector — Phase B
  # revisits this with the contest-snapshot policy.
  def finish
    unless @current_user == @submission.user
      redirect_to viva_submission_path(@submission), alert: 'Only the owner can end their viva.' and return
    end
    unless @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission), alert: 'Finish is only available for viva exam problems.' and return
    end
    if @submission.problem.viva_daily_limit == 0 && !@submission.test_drive?
      redirect_to viva_submission_path(@submission), alert: 'Contest vivas cannot be ended early.' and return
    end

    # Same row lock as #answer: a double-click on End used to write two
    # closing turns and queue two grade jobs for one interview.
    outcome = @submission.with_lock do
      next :ended     unless @submission.status.to_s == 'submitted'
      next :archived  if @submission.viva_archived_at.present?
      next :busy      if @submission.viva_turns.where(status: :processing).exists?
      next :no_answer unless @submission.viva_turns.where(role: :student).exists?

      force_finish!('(student ended the interview — grading begins)')
      :finished
    end

    case outcome
    when :ended
      redirect_to viva_submission_path(@submission), alert: 'This viva session has already ended.'
    when :archived
      redirect_to viva_submission_path(@submission), alert: 'This viva session has been archived.'
    when :busy
      redirect_to viva_submission_path(@submission), alert: 'Wait for the current response to finish first.'
    when :no_answer
      redirect_to viva_submission_path(@submission), alert: 'Answer at least one question first — or use Restart to start over.'
    when :finished
      Llm::VivaGradeAssistJob.perform_later(@submission)
      redirect_to viva_submission_path(@submission), notice: 'Interview ended — grading has started.'
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

  # Ends the interview and hands the transcript to the grader: closing system
  # turn + status :evaluating. Call only inside `@submission.with_lock` — the
  # lock is what stops two concurrent requests from both taking this step —
  # and enqueue Llm::VivaGradeAssistJob AFTER the lock block has committed.
  def force_finish!(closing_note)
    @submission.viva_turns.create!(role: :system, status: :ok, content: closing_note)
    @submission.update!(status: :evaluating)
  end

  # Creates a viva session for @current_user on `problem` and kicks off the
  # greeting: the Submission row, the "(interview start)" system turn, the
  # :processing assistant placeholder, and Llm::VivaTurnAssistJob once the
  # transaction has committed. Shared by #start (real sessions), #test_drive
  # and the test-drive branch of #restart, so the three can never drift.
  # `language` is the viva Language the caller has already resolved.
  def create_viva_session!(problem, language, test_drive: false)
    submission = nil
    placeholder = nil
    Submission.transaction do
      submission = Submission.create!(
        user:     @current_user,
        problem:  problem,
        language: language,
        source:   nil,
        source_filename: nil,
        status:   :submitted,
        submitted_at: Time.zone.now,
        ip_address: request.remote_ip,
        test_drive: test_drive
      )
      submission.viva_turns.create!(role: :system, status: :ok, content: '(interview start)')
      placeholder = submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    end
    Llm::VivaTurnAssistJob.perform_later(submission, turn: placeholder)
    submission
  end

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

  # Gates #show/#refresh: reuses the platform's existing submission-view
  # predicate (admin -> reporter -> problem-submittable gate -> owner ->
  # global `right.user_view_submission` -> per-problem `view_submission`)
  # rather than duplicating that logic here. Without this, any logged-in
  # student could read any other student's viva transcript/grade by
  # guessing sequential submission ids.
  def authorize_viva_view
    return if @current_user.can_view_submission?(@submission)

    redirect_to list_main_path, alert: 'Authorization error: you are not allowed to view this viva session.'
  end
end
