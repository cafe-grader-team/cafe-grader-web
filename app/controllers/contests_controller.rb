class ContestsController < ApplicationController
  before_action :set_contest, only: [:show, :edit, :update, :destroy, :view, :view_query,
                                     :ai_usage, :ai_usage_query, :finish_open_vivas, :viva_status, :viva_check,
                                     :add_users_from_csv, :clone, :set_active,
                                     :show_users_query, :show_problems_query,
                                     :add_user, :add_user_by_group, :add_problem, :add_problem_by_group,
                                     :do_all_users, :do_user, :extra_time_user, :do_all_problems, :do_problem, :reorder_problems,
                                     :add_comment, :update_comment, :delete_comment,
                                    ]
  before_action :set_user, only: [:do_user]
  before_action :set_problem, only: [:do_problem]

  USER_ACTION = [:user_check_in, :set_active]
  EDITOR_ACTION = %i[show edit update destroy view view_query ai_usage ai_usage_query finish_open_vivas viva_status viva_check clone
                     show_users_query show_problems_query
                     add_users_from_csv add_user add_user_by_group
                     add_problem add_problem_by_group
                     do_all_users do_user extra_time_user do_all_problems do_problem reorder_problems
                     add_comment update_comment delete_comment
                    ]
  before_action :check_valid_login
  before_action :group_editor_authorization, except: USER_ACTION
  before_action :can_manage_contest, only: EDITOR_ACTION

  before_action :check_finalized, only: %i[add_user_by_group add_user add_users_from_csv
                                           add_problem add_problem_by_group do_all_problems
                                           do_all_users do_user extra_time_user do_all_problems do_problem reorder_problems
                                          ]
  delegate :pluralize, to: 'ActionController::Base.helpers'

  # GET /contests
  # GET /contests.xml
  def index
    respond_to do |format|
      format.html # index.html.erb
    end
  end

  def index_query
    @contests_for_manage = @current_user.contests_for_action(:edit)
    render json: {data: @contests_for_manage,
                  userCount: ContestUser.where(contest_id: @contests_for_manage.ids).group('contest_id').count('user_id'),
                  probCount: ContestProblem.where(contest_id: @contests_for_manage.ids).group('contest_id').count('problem_id') }
  end

  # GET /contests/1
  # GET /contests/1.xml
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render xml: @contest }
    end
  end

  # show is for manage
  # view is for spectating, showing score graph and table
  def view
    @problems = @contest.problems.order(:number)
  end

  def view_query
    @result = @contest.score_report

    render json: {
      data: @contest.contests_users.joins(:user)
        .where(role: 'user')
        .select(:id, :user_id, :login, :full_name, :remark, :seat, :last_heartbeat),
      result: @result,
      problem: @contest.problems.select(:id, :name).order(:number)
    }
  end

  # GET /contests/:id/ai_usage — read-only LLM usage overview for this contest
  # (viva interviews, grading, and submission assists): volume, cost, and
  # response-time percentiles over the contest window.
  def ai_usage
    @report = AiUsageReport.new(@contest)
  end

  # POST /contests/:id/ai_usage_query — per-call feed for the DataTable.
  def ai_usage_query
    render json: { data: AiUsageReport.new(@contest).calls_json }
  end

  # GET /contests/:id/viva_status — the viva grading status line next to
  # "Finish open vivas", re-fetched into its turbo frame every 10 s while
  # anything is still grading (contests/_viva_status).
  def viva_status
    render partial: 'viva_status', locals: {contest: @contest}
  end

  # GET /contests/:id/viva_check — the Viva check page (design 2026-10-07,
  # §4): per student, per viva problem, the flags staff should act on during
  # the exam or look at afterwards. The body reloads itself every 30 s while
  # the contest runs; its only write is the per-row "Allow another attempt"
  # (SubmissionsController#allow_viva_retake, which re-renders the body).
  def viva_check
    @report = VivaCheckReport.new(@contest)
  end

  # POST /contests/:id/finish_open_vivas — the "Finish open vivas" button.
  # Runs Contest#finish_open_vivas! once and toasts the three counts. Not
  # behind check_finalized on purpose: the 24 h reaper grades open sessions
  # whatever that flag says, so gating here would add friction without a
  # guarantee. One audit row carries the counts when anything changed.
  def finish_open_vivas
    counts = @contest.finish_open_vivas!
    @toast = {title: "Contest #{@contest.name}"}
    if counts.values.sum.zero?
      @toast[:body] = 'No open viva sessions.'
    else
      body = "Sent #{pluralize(counts[:graded], 'session')} to grading, archived #{pluralize(counts[:archived], 'greeting-only session')}."
      if counts[:skipped].positive?
        body += " Skipped #{pluralize(counts[:skipped], 'session')} with a reply in flight — click again in a minute."
        @toast[:type] = :warning
      end
      @toast[:body] = body
    end

    if (counts[:graded] + counts[:archived]).positive?
      AuditLog.record!(auditable: @contest, action: 'finish_open_vivas',
                       object_changes: { 'graded_count'   => [nil, counts[:graded]],
                                         'archived_count' => [nil, counts[:archived]],
                                         'skipped_count'  => [nil, counts[:skipped]] })
    end
    # Toast plus an in-place refresh of the button's open-session badge, so the
    # count drops to what is left (the skipped ones) without a reload.
    render turbo_stream: [
      turbo_stream.append('toast-area', partial: 'toast', locals: {toast: @toast}),
      turbo_stream.update('open-viva-count', @contest.open_viva_sessions.count.to_s),
    ]
  end

  # GET /contests/new
  # GET /contests/new.xml
  def new
    @contest = Contest.new(start: Time.zone.now, stop: Time.zone.now+3.hour)

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render xml: @contest }
    end
  end

  def clone
    new_contest = Contest.new(description: @contest.description, start: Time.zone.now, stop: Time.zone.now+3.hour,
                            outside_login_off: @current_user.admin? && @contest.outside_login_off)
    new_contest.name = new_contest.get_next_name(@contest.name + '_copy')
    @contest.contests_users.each { |cu| new_contest.contests_users.build(user_id: cu.user_id, role: cu.role) }
    @contest.contests_problems.each { |cp| new_contest.contests_problems.build(problem_id: cp.problem_id, number: cp.number) }

    saved = nil
    AuditLog.paused do
      saved = new_contest.save
    end

    if saved
      AuditLog.record!(
        auditable:      new_contest,
        action:         'clone',
        object_changes: {
          'source_contest'  => [nil, @contest.name],
          'users_copied'    => [nil, new_contest.contests_users.size],
          'problems_copied' => [nil, new_contest.contests_problems.size]
        }.merge(new_contest.outside_login_off? ? {'outside_login_off' => [nil, true]} : {})
      )
      redirect_to contest_path(new_contest), notice: "Contest \"#{@contest.name}\" is cloned to this contest"
    else
      render partial: 'msg_modal_show', locals: {do_popup: true,
                                                 header_msg: 'Contest Cloning Error',
                                                 header_class: 'bg-danger-subtle',
                                                 error_messages: new_contest.errors.full_messages}
    end
  end

  # GET /contests/1/edit
  def edit
  end

  # POST /contests
  # POST /contests.xml
  def create
    @contest = Contest.new(contests_params)
    @contest.add_users(User.where(id: @current_user.id), role: 'editor')

    respond_to do |format|
      if @contest.save
        flash[:notice] = 'Contest was successfully created.'
        format.html { redirect_to contests_path }
        format.xml  { render xml: @contest, status: :created, location: @contest }
      else
        format.html { render action: "new" }
        format.xml  { render xml: @contest.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /contests/1
  # PUT /contests/1.xml
  def update
    respond_to do |format|
      if @contest.update(contests_params)
        flash[:notice] = 'Contest was successfully updated.'
        format.html { redirect_to contest_path(@contest) }
        format.xml  { head :ok }
      else
        format.html { render action: "edit" }
        format.xml  { render xml: @contest.errors, status: :unprocessable_entity }
      end
    end
  end

  def contest_action
    @contest = Contest.find(params[:contest_id])
    @toast = {title: "Contest #{@contest.name}"}
    case params[:command]
    when 'toggle'
      @contest.update(enabled: !@contest.enabled?)
      @toast[:body] = @contest.enabled? ? 'Contest was enabled.' : 'Contest was disaabled.'
    else
      @toast[:body] = "Unknown command"
    end
    render turbo_stream: [
      turbo_stream.append('toast-area', partial: 'toast', locals: {toast: @toast}),
      turbo_stream.append('toast-area', partial: 'event_dispatcher', locals: {event_name: 'datatable:reload', event_detail: { "h": 1}}),
    ]
  end

  # --- users & problems ---
  def show_users_query
    render json: {data: @contest.contests_users.joins(:user)
      .select('contests_users.id', :user_id, :contest_id, :enabled, :full_name, :role, :login, :remark, :seat, :extra_time_second, :start_offset_second)}
  end

  def show_problems_query
    # D1's practice-viva forgotten-toggle guard (and the columns it needed)
    # was removed along with the underlying practice/exam toggle
    # (2026-07-21 context-policy design, Phase A) — nothing in
    # contestManageProblem reads compilation_type here anymore either.
    rows = @contest.contests_problems.joins(:problem)
      .select('contests_problems.id', :problem_id, :contest_id, :available, :enabled, :allow_llm, :name, :full_name, :number)
      .reorder('contests_problems.number', 'contests_problems.id')
    data = rows.each_with_index.map { |r, i| r.as_json.merge('position' => i + 1) }
    render json: {data: data}
  end

  def do_all_users
    @toast = {title: "Contest #{@contest.name}"}
    affected_count = @contest.contests_users.count
    audit_action = nil
    audit_changes = nil

    case params[:command]
    when 'enable'
      AuditLog.paused { ContestUser.where(contest: @contest).update_all(enabled: true) }
      @toast[:body] = "All users were enabled."
      audit_action = 'bulk_enable_users'
      audit_changes = { 'affected_count' => [nil, affected_count] }
    when 'disable'
      AuditLog.paused { ContestUser.where(contest: @contest).update_all(enabled: false) }
      @toast[:body] = "All users were disabled."
      audit_action = 'bulk_disable_users'
      audit_changes = { 'affected_count' => [nil, affected_count] }
    when 'remove'
      AuditLog.paused { @contest.users.clear }
      @toast[:body] = "All users were removed."
      audit_action = 'bulk_remove_users'
      audit_changes = { 'removed_count' => [nil, affected_count] }
    when 'clear_ip'
      AuditLog.paused { @contest.users.update_all(last_ip: nil) }
      @toast[:body] = "Device locks of all users are cleared. The user can now log in from a new device."
      audit_action = 'bulk_clear_user_ips'
      audit_changes = { 'affected_count' => [nil, affected_count] }
    else
      @toast[:body] = "ERROR: Unknown command"
      @toast[:type] = :alert
    end

    AuditLog.record!(auditable: @contest, action: audit_action, object_changes: audit_changes) if audit_action

    @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'user_table'}}
    render 'turbo_toast'
  end

  def do_user
    @toast = {title: "Contest #{@contest.name}"}
    case params[:command]
    when 'remove'
      AuditLog.paused { @contest.users.delete(@user) }
      AuditLog.record!(
        auditable:      @contest,
        action:         'remove_user',
        object_changes: { 'user' => [@user.login, nil] }
      )
      @toast[:body] = "#{@user.login} was removed."
    when 'toggle'
      gu = @contest.contests_users.where(user: @user).first
      gu.update(enabled: !gu.enabled?)
      @toast[:body] = 'User was updated.'
    when 'clear_ip'
      @user.update(last_ip: nil)
      @toast[:body] = 'User session was cleared.'
    when 'make_editor', 'make_user'
      target_role = params[:command].split('_')[1]

      if @user != @current_user || @user.admin? || target_role == 'editor'
        ContestUser.where(user: @user, contest: @contest).update(role: target_role)
        @toast[:body] = "#{@user.login}'s role changed to #{target_role}."
      else
        @toast[:body] = "Cannot demote yourself"
        @toast[:type] = :alert
      end
    else
      @toast[:body] = "Unknown command"
      @toast[:type] = :alert
    end
    @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'user_table'}}
    render 'turbo_toast'
  end

  def extra_time_user
    cu = @contest.contests_users.find(params[:row_id])
    # A cleared field means "no extra time", not NULL.
    start_offset = params[:start_offset].presence || 0
    end_offset = params[:end_offset].presence || 0
    if cu.update(start_offset_second: start_offset, extra_time_second: end_offset)
      @toast = {title: "Contest #{@contest.name}", body: "Set extra times of #{cu.user.login} to #{cu.start_offset_second} : #{cu.extra_time_second} seconds"}
      @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'user_table'}}
    else
      @toast = {title: "Extra time not saved", body: cu.errors.full_messages.to_sentence, type: :alert}
    end
    render 'turbo_toast'
  end

  def do_all_problems
    affected_count = @contest.contests_problems.count
    audit_action = nil

    case params[:command]
    when 'enable'
      AuditLog.paused { ContestProblem.where(contest: @contest).update_all(enabled: true) }
      audit_action = 'bulk_enable_problems'
    when 'disable'
      AuditLog.paused { ContestProblem.where(contest: @contest).update_all(enabled: false) }
      audit_action = 'bulk_disable_problems'
    when 'remove'
      AuditLog.paused { @contest.problems.clear }
      audit_action = 'bulk_remove_problems'
    else
      return
    end

    AuditLog.record!(
      auditable:      @contest,
      action:         audit_action,
      object_changes: { (audit_action == 'bulk_remove_problems' ? 'removed_count' : 'affected_count') => [nil, affected_count] }
    )

    @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'problem_table'}}
    render 'turbo_toast'
  end

  def do_problem
    @toast = {title: "Contest #{@contest.name}", body: "The problem #{@problem.name} was updated."}
    gp = @contest.contests_problems.where(problem: @problem).first
    case params[:command]
    when 'remove'
      AuditLog.paused { @contest.problems.delete(@problem) }
      AuditLog.record!(
        auditable:      @contest,
        action:         'remove_problem',
        object_changes: { 'problem' => [@problem.name, nil] }
      )
      @toast[:body] = "Problem #{@problem.name} was removed."
    when 'toggle'
      gp.update(enabled: !gp.enabled?)
    when 'toggle_llm'
      gp.update(allow_llm: !gp.allow_llm?)
    when 'moveup', 'movedown'
      old_number = gp.number
      AuditLog.paused do
        @contest.move_problem(@problem, params[:command] == 'moveup' ? :up : :down)
      end
      new_number = @contest.contests_problems.where(problem: @problem).first&.number
      AuditLog.record!(
        auditable:      @contest,
        action:         params[:command] == 'moveup' ? 'move_up' : 'move_down',
        object_changes: { 'problem' => [nil, @problem.name], 'number' => [old_number, new_number] }
      )
      @toast[:body] = "Problem #{@problem.name} was #{params[:command] == 'moveup' ? 'moved up' : 'moved down'}."
    else
      @toast[:body] = "Unknown command"
      @toast[:type] = 'alert'
    end
    @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'problem_table'}}
    render 'turbo_toast'
  end

  # POST: save the problem order sent by drag-and-drop (problem_order = comma-separated problem ids)
  def reorder_problems
    before = @contest.problems_in_display_order.map(&:problem)
    AuditLog.paused { @contest.reorder_problems!(params[:problem_order].to_s.split(',')) }
    after_ids = @contest.problems_in_display_order.map(&:problem_id)
    if after_ids != before.map(&:id)
      names = before.index_by(&:id).transform_values(&:name)
      AuditLog.record!(
        auditable:      @contest,
        action:         'reorder_problems',
        object_changes: { 'order' => [before.map(&:name), after_ids.map { |i| names[i] }] }
      )
    end
    @toast = {title: "Contest #{@contest.name}", body: "The problem order was saved."}
    @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'problem_table'}}
    render 'turbo_toast'
  end

  def add_user
    begin
      users = User.where(id: params[:user_ids])
      result = nil
      AuditLog.paused do
        result = @contest.add_users users
        @toast = save_adding_and_build_toast(result, User.name.downcase)
      end
      AuditLog.record!(
        auditable:      @contest,
        action:         'bulk_add_users',
        object_changes: {
          'user_ids'      => [nil, Array(params[:user_ids]).map(&:to_i)],
          'added_count'   => [nil, result.added],
          'skipped_count' => [nil, result.skipped]
        }
      )
      @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'user_table'}}
      render 'turbo_toast'
    rescue => e
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Adding users failed', body_msg: e.message}
    end
  end

  def add_user_by_group
    begin
      user_ids = GroupUser.where(group_id: params[:user_group_ids]).pluck :user_id
      result = nil
      AuditLog.paused do
        result = @contest.add_users User.where(id: user_ids)
        @toast = save_adding_and_build_toast(result, User.name.downcase)
      end
      AuditLog.record!(
        auditable:      @contest,
        action:         'bulk_add_users_by_group',
        object_changes: {
          'group_ids'     => [nil, Array(params[:user_group_ids])],
          'added_count'   => [nil, result.added],
          'skipped_count' => [nil, result.skipped]
        }
      )
      @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'user_table'}}
      render 'turbo_toast'
    rescue => e
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Adding users failed', body_msg: e.message}
    end
  end

  def add_users_from_csv
    lines = params[:user_list]

    res = nil
    AuditLog.paused do
      res = @contest.add_users_from_csv(lines)
    end
    @toast = {title: "Contest #{@contest.name}"}
    body = "#{pluralize(res[:added_users].count, 'user')} were added or updated. "
    body += "#{pluralize(res[:error_logins].count, 'user')} failed to be added. The first error is #{res[:first_error]}" if res[:error_logins].count > 0
    @toast[:body] = body
    AuditLog.record!(
      auditable:      @contest,
      action:         'bulk_add_users_by_csv',
      object_changes: {
        'added_count'  => [nil, res[:added_users].count],
        'failed_count' => [nil, res[:error_logins].count]
      }
    )
    @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'user_table'}}
    render 'turbo_toast'
  end

  def add_problem
    # find return arrays of objecs
    begin
      # this find multiple problems that matches the ID that is also editable by the user
      problems = @current_user.problems_for_action(:edit).where(id: params[:problem_ids])
      result = nil
      AuditLog.paused do
        result = @contest.add_problems_and_assign_number(problems)
        @toast = save_adding_and_build_toast(result, Problem.name.downcase)
      end
      AuditLog.record!(
        auditable:      @contest,
        action:         'bulk_add_problems',
        object_changes: {
          'problem_ids'   => [nil, Array(params[:problem_ids]).map(&:to_i)],
          'added_count'   => [nil, result.added],
          'skipped_count' => [nil, result.skipped]
        }
      )
      @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'problem_table'}}
      render 'turbo_toast'
    rescue => e
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Adding problems failed', body_msg: e.message}
    end
  end

  def add_problem_by_group
    begin
      problem_ids = GroupProblem.where(group_id: params[:problem_group_ids]).where.not(problem_id: @contest.problems.ids).pluck :problem_id
      problems = Problem.group_editable_by_user(@current_user).where(id: problem_ids)
      result = nil
      AuditLog.paused do
        result = @contest.add_problems_and_assign_number(problems)
        @toast = save_adding_and_build_toast(result, Problem.name.downcase)
      end
      AuditLog.record!(
        auditable:      @contest,
        action:         'bulk_add_problems_by_group',
        object_changes: {
          'group_ids'     => [nil, Array(params[:problem_group_ids])],
          'added_count'   => [nil, result.added],
          'skipped_count' => [nil, result.skipped]
        }
      )
      @event_dispatcher = {event_name: 'datatable:reload', event_detail: { "table": 'problem_table'}}
      render 'turbo_toast'
    rescue => e
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Adding problems failed', body_msg: e.message}
    end
  end



  # DELETE /contests/1
  # DELETE /contests/1.xml
  def destroy
    @contest.destroy

    render turbo_stream: turbo_stream.append('js-response', partial: 'event_dispatcher',
      locals: {event_name: 'datatable:reload', event_detail: { "h": 1}})
  end

  # ---- contest comments ----
  # Staff notes on the contest (design 2026-11-18). Anyone who can manage the
  # contest reads, adds, edits and deletes. Deliberately NOT behind
  # check_finalized: the after-action report is written once the contest is
  # over and finalized. No audit row — each comment carries author and time.
  def add_comment
    comment = @contest.comments.new(kind: :comment, user: @current_user, body: params[:body].to_s.strip)
    if comment.save
      render_comments(title: 'Comment added')
    else
      render_comments(title: 'Comment not added', body: comment.errors.full_messages.to_sentence, type: :alert)
    end
  end

  def update_comment
    comment = @contest.comments.find(params[:comment_id])
    if comment.update(body: params[:body].to_s.strip)
      render_comments(title: 'Comment updated')
    else
      render_comments(title: 'Comment not updated', body: comment.errors.full_messages.to_sentence, type: :alert)
    end
  end

  def delete_comment
    @contest.comments.find(params[:comment_id]).destroy
    render_comments(title: 'Comment deleted')
  end

  def set_system_mode
    # Switching the whole site's mode is an admin-only act. It was reachable by
    # any group editor (this controller is only editor-gated) — a TA flipped the
    # site's mode mid-exam on 2026-09-09. admin_authorization redirects non-admins.
    return unless admin_authorization

    unless ['standard', 'contest', 'indv-contest', 'analysis'].include? params[:mode]
      redirect_to contests_path, notice: 'Unrecognized mode' and return
    end

    # An exam mode needs an explicit IP-whitelist choice, ON or OFF, with no
    # default: the Contest button's dialog sends `whitelist`. One site-wide
    # allowed list cannot fit every course — one exam sits in a lab on the
    # list, another on the campus network, a makeup at home (design
    # 2026-11-18, revised 2026-11-19).
    exam = ['contest', 'indv-contest'].include?(params[:mode])
    if exam && !['on', 'off'].include?(params[:whitelist])
      redirect_to contests_path, notice: 'Mode not changed: choose whether the IP whitelist is ON or OFF.' and return
    end

    mode_row = GraderConfiguration.find_by(key: 'system.mode')
    old_mode = mode_row.value
    old_whitelist_ignore = GraderConfiguration.find_by(key: GraderConfiguration::WHITELIST_IGNORE_KEY)&.value

    AuditLog.paused do
      mode_row.update(value: params[:mode])
      GraderConfiguration.set_exam_mode(exam)
      GraderConfiguration.set_whitelist(exam && params[:whitelist] == 'on')
    end
    new_whitelist_ignore = GraderConfiguration.find_by(key: GraderConfiguration::WHITELIST_IGNORE_KEY)&.value

    AuditLog.record!(
      auditable:      mode_row,
      action:         'mode_change',
      object_changes: {
        'system.mode' => [old_mode, params[:mode]],
        # the IP whitelist as chosen (Contest) or turned off (Normal,
        # Analysis); dropped from the row when the switch did not change it
        GraderConfiguration::WHITELIST_IGNORE_KEY => [old_whitelist_ignore, new_whitelist_ignore]
      }.reject { |_key, (old, new)| old == new }
    )

    redirect_to contests_path, notice: mode_changed_notice(params[:mode])
  end

  # ---- user action ----
  def set_active
    # validate
    unless @contest.users.include?(@current_user) && @contest.enabled?
      redirect_to list_main_path, error: 'You are not part of the selected contest'
    else
      session[:contest_id] = @contest.id
      redirect_to list_main_path
    end
  end

  def user_check_in
    # ContestUser.where(id: Contest.active.joins(:contests_users).where(contests_users: {user_id: @current_user}).pluck('contests_users.id')).update_all(last_heartbeat: Time.zone.now)
    current = Time.zone.now
    last = @current_user.last_heartbeat || current
    @current_user.update(last_heartbeat: current)
    ms_since_last_check_in = ((current - last) * 1000).to_i
    if @current_contest
      ms_until_contest_end = ((@current_contest.stop - current) * 1000).to_i

      cu = ContestUser.where(contest: @current_contest, user: @current_user)
      cu.update(last_heartbeat: current) if cu
    end
    render json: {ms_since_last_check_in: ms_since_last_check_in, ms_until_contest_end: ms_until_contest_end, current_time: current}
  end


  private

    # Redraw the Comments card and show a toast.
    def render_comments(title:, body: nil, type: :notice)
      @toast = {title: title, body: body.to_s, type: type}
      render turbo_stream: [
        turbo_stream.replace('contest-comments', partial: 'contests/comments', locals: {contest: @contest}),
        turbo_stream.append('toast-area', partial: 'toast', locals: {toast: @toast})
      ]
    end

    # The notice after a mode switch says what happened to the IP whitelist —
    # a stale or empty allowed list is seen at once.
    def mode_changed_notice(mode)
      GraderConfiguration.read_config
      msg = "Mode changed to #{helpers.mode_to_text(mode)}."
      return "#{msg} IP whitelist is now off." unless GraderConfiguration.whitelist_active?
      ranges = GraderConfiguration.whitelist_ranges
      if ranges.empty?
        "#{msg} IP whitelist is now ON and the allowed list is EMPTY — no student can get in, only admins and problem editors."
      else
        "#{msg} IP whitelist is now ON — allowed: #{ranges.join(', ')}"
      end
    end

    def set_contest
      @contest = Contest.find(params[:id])
    end

    def set_user
      @user = User.find(params[:user_id]) rescue nil
    end

    def set_problem
      @problem = Problem.find(params[:problem_id]) rescue nil
    end

    def can_manage_contest
      @contests_for_manage = @current_user.contests_for_action(:edit)
      unauthorized_redirect(msg: "You cannot manage this contest") if @contests_for_manage.where(id: @contest.id).none?
    end

    def contests_params
      if @contest && @contest.finalized?
        params.require(:contest).permit(:finalized)
      else
        permitted = %i[name description enabled lock start stop finalized]
        permitted << :outside_login_off if @current_user.admin? && User.outside_login_available?
        params.require(:contest).permit(*permitted)
      end
    end

    def check_finalized
      if @contest.finalized?
        render partial: 'error_modal', locals: {title: 'Contest update error', body: 'The contest is finalized. It cannot be modified unless it is de-finalized first'}
      end
    end

    def save_adding_and_build_toast(result, association_name)
      if @contest.save
        if result.added == 0
          if result.skipped == 0
            return {title: "Contest's #{association_name.pluralize} are NOT changed", body: "No #{association_name.pluralize} are given."}
          else
            return {title: "Contest's #{association_name.pluralize} are NOT changed", body: "All given #{association_name.pluralize} are already in the contest."}
          end
        else
          if result.skipped == 0
            return {title: "Contest's #{association_name.pluralize} changed", body: "All given #{association_name.pluralize} have been added to the contest."}
          else
            return {title: "Contest's #{association_name.pluralize} changed",
                    body: %Q(
                      From given #{pluralize(result.added + result.skipped, association_name)},
                      #{pluralize(result.added, association_name)} were added to the contest
                      while the other #{pluralize(result.skipped, association_name)} are already in the contest.
                    )}
          end
        end
      else
        return {title: "Contest Update Error!",
                body: "Contest <code>#{@contest.name}</code> cannot be updated",
                errors: @contest.errors.full_messages,
                type: :alert}
      end
    end
end
