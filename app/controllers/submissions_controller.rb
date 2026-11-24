class SubmissionsController < ApplicationController
  include ProblemAuthorization
  include SubmissionAuthorization

  before_action :check_valid_login

  before_action :set_submission, only: [:show, :show_comments, :download, :compiler_msg, :rejudge, :set_tag, :edit, :evaluations, :allow_viva_retake, :adopt_viva_grade]
  before_action :set_problem, only: %i[ edit direct_edit_problem rejudge set_tag allow_viva_retake adopt_viva_grade ]
  before_action :set_language, only: %i[ edit direct_edit_problem ]

  before_action :can_view_submission, only: [:show, :show_comments, :download, :edit, :evaluations, :compiler_msg]
  before_action :can_view_problem, only: [ :direct_edit_problem ]
  before_action :can_edit_problem, only: [:rejudge, :set_tag, :allow_viva_retake, :adopt_viva_grade]

  # GET /submissions                  My Submissions, all problems (issue #62)
  # GET /submissions/prob/:problem_id  ... narrowed to one problem
  # 50 rows a page, newest first: a student may hold thousands of submissions
  # (the heaviest on production has ~20k), so the page never loads them all.
  PER_PAGE = 50

  def index
    @problems = @current_user.problems_for_action(:submit)

    if params[:problem_id].present?
      @problem = Problem.find_by(id: params[:problem_id])
      if @problem.nil? || !@current_user.can_view_problem?(@problem)
        redirect_to list_main_path
        flash[:error] = 'Authorization error: You have no right to view submissions for this problem'
        return
      end
    end

    scope = Submission.regular.where(user: @current_user)
    if @problem
      scope = scope.where(problem: @problem)
    elsif !@current_user.admin?
      # All problems (issue #62): only the problems the student may open —
      # the same report ∪ submit set User#can_view_problem? checks — so every
      # row links to a page that will actually render.
      scope = scope.where(problem_id: @current_user.problems_for_action(:submit))
                   .or(scope.where(problem_id: @current_user.problems_for_action(:report)))
    end
    # when in contest mode, show only submissions made during the active contests
    scope = scope.where(submitted_at: @current_user.active_contests_range) if GraderConfiguration.contest_mode?

    @total_count = scope.count
    @per_page    = PER_PAGE
    @total_pages = [(@total_count.to_f / @per_page).ceil, 1].max
    @page        = params[:page].to_i.clamp(1, @total_pages)
    @submissions = scope.order(id: :desc)
                        .offset((@page - 1) * @per_page).limit(@per_page)
                        .includes(:problem, :language)

    @sub_details = Hash.new { |h, k| h[k] = {} }
    Comment
      .where(kind: ['llm_assist'], commentable_id: @submissions.map(&:id))
      .group(:commentable_id)
      .select(:commentable_id, "count(comments.id) as llm_count", "sum(comments.cost) as llm_cost")
      .each { |row| @sub_details[row.commentable_id] = { count: row.llm_count, cost: row.llm_cost } }
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
      # There's no submission yet, so there's nothing to view — and
      # viva/start is POST-only (redirect_to can't replay it as a POST;
      # a plain redirect here would 404), so send the student back to the
      # problem list where the real "Start Viva" button lives.
      redirect_to list_main_path,
                  alert: "'#{@problem.name}' is a viva exam — use \"Start Viva\" from the problem list to begin." and return
    end
    @last_sub = @current_user.last_submission_by_problem(@problem)
    @models = [] # won't allow llm models on the first submission
    @submission_source = nil
    # a reporter can VIEW a problem hidden from students without being able to
    # submit — render the page view-only instead of a submit form that would
    # only fail at POST time
    @can_submit = @current_user.can_submit_to_problem?(@problem)
    render 'edit'
  end

  # GET /submissions/1/edit
  def edit
    if @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission) and return
    end
    @last_sub = @current_user.last_submission_by_problem(@problem)
    @models = Rails.configuration.llm[:provider].keys
    @submission_source = @submission&.source unless @as_binary
    @can_submit = @current_user.can_submit_to_problem?(@problem)
  end

  # as Turbo
  def get_latest_submission_status
    @problem = Problem.find(params[:pid])
    @submission = @current_user.last_submission_by_problem(@problem)
    @delay_value = @submission.nil? ? -1 : (Time.zone.now - @submission.submitted_at).clamp(1, 10).to_i * 1000
    sub_count = Submission.regular.where(user: @current_user, problem: @problem).count
    render turbo_stream: [
      turbo_stream.update("latest_status",
                           partial: 'submission_short',
                           locals: {submission: @submission,
                                    refresh_if_not_graded: @delay_value > 0,
                                    show_id: true,
                                    sub_count: sub_count,
                                    show_button: false })
    ]
  end
  # Turbo render evaluations as modal popup
  def evaluations
    if @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission) and return
    end
    @testcases = @submission.problem.live_dataset.testcases.order(:group, :num)
    @evaluations_by_tcid = Evaluation.where(submission: @submission, testcase: @testcases.ids).index_by(&:testcase_id)
    render partial: 'msg_modal_show', locals: { do_popup: true, header_msg: 'Evaluation Details', body_msg: render_to_string(partial: 'evaluations', locals: {testcases: @testcases, evaluations_by_tcid: @evaluations_by_tcid}) }
  end

  def download
    if @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission) and return
    end
    if @submission.language.binary? && @submission.binary
      send_data @submission.binary, filename: @submission.download_filename, type: @submission.content_type || 'application/octet-stream', disposition: 'attachment'
      return
    end

    # no binary, send the source
    send_data(@submission.source, {filename: @submission.download_filename, type: 'text/plain'})
  end

  def compiler_msg
    if @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission) and return
    end
    render partial: "msg_modal_show", locals: {do_popup: true, header_msg: "Compiler message for ##{@submission.id}", body_msg: helpers.content_tag(:pre, @submission.compiler_message)}
  end

  # POST /submissions/:id/rejudge
  # Viva: one more grader run (Submission#regrade_viva!). The current grade
  # is kept and stays visible to the student until the new run is adopted;
  # never_lower=1 (the "Keep the higher grade" box) files a lower run away
  # instead of applying it. Code submissions: a lower-priority judge job.
  def rejudge
    if @submission.problem.viva_exam?
      never_lower = params[:never_lower] == '1'
      begin
        @submission.regrade_viva!(model: params[:model].presence, never_lower: never_lower, requested_by: @current_user)
        model_label = params[:model].presence || 'default model'
        rule = never_lower ? 'keeps the higher grade' : 'replaces the current grade'
        @toast = {title: 'Re-grading',
                  body: "Submission ##{@submission.id} grading queued (#{model_label}; #{rule}). The current grade stays until the new run is adopted."}
      rescue Submission::NotRegradable => e
        @toast = {title: 'Re-grading', body: "Cannot re-run grading: #{e.message}.", type: :alert}
      end
    else
      # add lower priority job
      @submission.add_judge_job(@submission.problem.live_dataset, -10)
      @toast = {title: 'Rejudge', body: "Submission ##{@submission.id} is added to judge queue."}
    end
    render 'turbo_toast'
  end

  # POST /submissions/:id/allow_viva_retake — "Allow another attempt" (design
  # 2026-10-07, A4; editors of the problem). Archives the session whatever its
  # status and stops it counting toward the start limit, so the student can
  # start exactly one more (Submission#grant_viva_retake!). One audit row on
  # the problem per grant; a second click changes nothing and says so.
  def allow_viva_retake
    # Grant and audit row commit together, or not at all.
    outcome = Submission.transaction do
      @submission.grant_viva_retake!(by: @current_user).tap do |result|
        if result == :granted
          AuditLog.record!(auditable: @submission.problem, action: 'viva_retake_grant',
                           object_changes: {'submission_id' => [nil, @submission.id],
                                            'user'          => [nil, @submission.user.login]})
        end
      end
    end
    # Read after the grant has committed: what the student can do now.
    policy  = Viva::StartPolicy.new(@submission.problem, @submission.user)
    message = allow_viva_retake_message(outcome, policy)
    # Green only when a start was actually freed; a grant that still leaves
    # the student without a start ("grant that one too") is a warning, so
    # staff notice it.
    freed = outcome == :granted && policy.refusal.nil?
    # From the contest's Viva check page (contest_id given): toast, and
    # re-render the report so the row updates at once — only for a contest
    # the staff member may manage. From the session page: back to it.
    if params[:contest_id].present?
      toast = {title: 'Allow another attempt', body: message, type: (freed ? :notice : :warning)}
      streams = [turbo_stream.append('toast-area', partial: 'toast', locals: {toast: toast})]
      if (contest = viva_check_contest)
        streams << turbo_stream.replace('viva-check-report', partial: 'contests/viva_check_report',
                                                              locals: {contest: contest, report: VivaCheckReport.new(contest)})
      end
      render turbo_stream: streams
    else
      flash_key = freed ? :notice : :alert
      redirect_to viva_submission_path(@submission), flash_key => message
    end
  end

  # POST /submissions/:id/viva/grades/:grade_id/adopt
  # "Make current" on the grade-history table: re-adopt an earlier valid run
  # (Submission#adopt_viva_grade!; the displaced run is labelled 'reverted').
  # Changes a student's score by hand, so one audit row goes on the problem.
  def adopt_viva_grade
    grade = @submission.viva_grades.find_by(id: params[:grade_id])
    unless grade
      redirect_to viva_submission_path(@submission), alert: 'No such grade run for this session.' and return
    end
    if @submission.status.to_s.in?(%w[submitted evaluating])
      redirect_to viva_submission_path(@submission),
                  alert: "Cannot change the grade while the interview or grading is in progress (status: #{@submission.status})." and return
    end
    if grade.failed?
      redirect_to viva_submission_path(@submission), alert: "Run ##{grade.id} produced no grade and cannot be made current." and return
    end
    if grade.current?
      redirect_to viva_submission_path(@submission), notice: "Run ##{grade.id} is already the current grade." and return
    end
    # The displaced run as read under the lock — a re-run that landed after
    # this page was rendered is what gets displaced, and what is audited.
    previous = @submission.adopt_viva_grade!(grade, reason: 'reverted')
    AuditLog.record!(auditable: @problem, action: 'viva_grade_adopt', object_changes: {
      'submission_id' => [nil, @submission.id],
      'grade_id'      => [previous&.id, grade.id],
      'points'        => [previous&.total_points&.to_f, grade.total_points.to_f]
    })
    redirect_to viva_submission_path(@submission),
                notice: "Run ##{grade.id} (#{grade.total_points}/100, #{grade.llm_model}) is now the current grade of viva session ##{@submission.id}."
  end

  def set_tag
    @submission.update(tag: params[:tag])
    redirect_to @submission
  end

protected
  def allow_viva_retake_message(outcome, policy)
    case outcome
    when :granted
      "Session ##{@submission.id} is closed and no longer counts toward the start limit#{retake_start_tail(policy)}"
    when :already
      "Session ##{@submission.id} already has a grant. It is closed and no longer counts toward the start limit#{retake_start_tail(policy)}"
    when :test_drive
      'A test-drive is outside the start limit; there is nothing to allow.'
    else
      'Not a viva session.'
    end
  end

  # What the student can do now, read from Viva::StartPolicy (`policy`, built
  # after the grant): the grant frees this session, but another answered
  # session of theirs today may still count, and a contest-only viva cannot
  # start outside contest mode.
  def retake_start_tail(policy)
    login = @submission.user.login
    if policy.refusal.nil?
      left = policy.starts_left
      ". #{login} may start another attempt at '#{@submission.problem.name}'" \
        "#{" (#{helpers.pluralize(left, 'start')} left today)" if left.is_a?(Integer)}."
    elsif policy.contest_only? && !GraderConfiguration.contest_mode?
      ', but this viva can be started only during a contest.'
    else
      ", but #{login} still has no start left today: another answered session of theirs today still counts. " \
        'Use Allow another attempt on that session too if they should start again.'
    end
  end

  # The contest a Viva check grant came from, when the user may manage it.
  def viva_check_contest
    @current_user.contests_for_action(:edit).find_by(id: params[:contest_id])
  end

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
