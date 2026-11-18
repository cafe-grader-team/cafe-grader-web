require "test_helper"

class ContestsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get contests_path
    assert_redirected_to login_main_path
  end

  test "normal user is redirected from contests index" do
    sign_in_as("john", "hello")
    get contests_path
    assert_redirected_to list_main_path
  end

  test "admin can access contests index" do
    sign_in_as("admin", "admin")
    get contests_path
    assert_response :success
  end

  test "group editor can access contests index" do
    sign_in_as("mary", "mary")
    get contests_path
    assert_response :success
  end

  # --- CRUD ---

  test "admin can create contest" do
    sign_in_as("admin", "admin")
    assert_difference "Contest.count" do
      post contests_path, params: {
        contest: {
          name: "new_contest",
          enabled: true
        }
      }
    end
  end

  test "admin can view contest" do
    sign_in_as("admin", "admin")
    get contest_path(contests(:contest_a))
    assert_response :success
  end

  test "admin can edit contest" do
    sign_in_as("admin", "admin")
    get edit_contest_path(contests(:contest_a))
    assert_response :success
  end

  test "admin can destroy contest" do
    sign_in_as("admin", "admin")
    contest = contests(:contest_c)
    assert_difference "Contest.count", -1 do
      delete contest_path(contest)
    end
  end

  # --- Cross-permission ---

  test "group editor (mary) can view their contest" do
    sign_in_as("mary", "mary")
    get contest_path(contests(:contest_a))
    assert_response :success
  end

  test "group editor (mary) cannot view a contest they don't own" do
    sign_in_as("mary", "mary")
    get contest_path(contests(:contest_b))
    assert_response :redirect
  end

  # --- Member actions ---

  test "admin can clone a contest" do
    sign_in_as("admin", "admin")
    assert_difference "Contest.count", +1 do
      get clone_contest_path(contests(:contest_a))
    end
  end

  test "admin can view contest score report" do
    sign_in_as("admin", "admin")
    get view_contest_path(contests(:contest_a))
    assert_response :success
  end

  test "admin can query contest scores as JSON" do
    sign_in_as("admin", "admin")
    post view_query_contest_path(contests(:contest_a))
    assert_response :success
  end

  test "admin can query contest users as JSON" do
    sign_in_as("admin", "admin")
    post show_users_query_contest_path(contests(:contest_a))
    assert_response :success
  end

  test "admin can query contest problems as JSON" do
    sign_in_as("admin", "admin")
    post show_problems_query_contest_path(contests(:contest_a))
    assert_response :success
  end

  # --- Collection actions ---

  test "admin can change system mode" do
    sign_in_as("admin", "admin")
    post set_system_mode_contests_path, params: { mode: "standard" }
    assert_response :redirect
  end

  # The IP whitelist follows the mode (design 2026-11-18): contest turns it on,
  # normal turns it off, the allowed list is never touched.
  test "contest mode turns the IP whitelist on and normal mode turns it off" do
    set_grader_config("right.whitelist_ip", "10.0.5.0/24, 192.0.2.7/32")
    sign_in_as("admin", "admin")

    assert_difference -> { AuditLog.where(action: "mode_change").count }, 1 do
      post set_system_mode_contests_path, params: { mode: "contest" }
    end
    reset_grader_config_cache
    assert GraderConfiguration.whitelist_active?
    assert_equal "10.0.5.0/24, 192.0.2.7/32", GraderConfiguration["right.whitelist_ip"]
    assert_match "IP whitelist is now ON — allowed: 10.0.5.0/24, 192.0.2.7/32", flash[:notice]
    changes = AuditLog.where(action: "mode_change").last.object_changes
    assert_equal %w[true false], changes["right.whitelist_ignore"]

    get contests_path
    assert_select "#whitelist-state", /ON.*Allowed:\s*10\.0\.5\.0\/24, 192\.0\.2\.7\/32/m

    post set_system_mode_contests_path, params: { mode: "standard" }
    reset_grader_config_cache
    assert_not GraderConfiguration.whitelist_active?
    assert_match "IP whitelist is now off", flash[:notice]
    get contests_path
    assert_select "#whitelist-state", /off.*Allowed when on:/m
  ensure
    reset_grader_config_cache
  end

  test "an empty allowed list is flagged on the mode card and in the notice" do
    set_grader_config("right.whitelist_ip", "")
    sign_in_as("admin", "admin")
    get contests_path
    assert_select "#whitelist-state.bg-danger-subtle", /allowed list is empty/

    post set_system_mode_contests_path, params: { mode: "contest" }
    assert_match "allowed list is EMPTY", flash[:notice]
  ensure
    reset_grader_config_cache
  end

  test "non-admin cannot change system mode" do
    set_grader_config("system.mode", "standard")
    sign_in_as("mary", "mary")   # a group editor — could flip the site's mode before B4
    post set_system_mode_contests_path, params: { mode: "contest" }
    assert_response :redirect
    assert_equal "standard", GraderConfiguration[GraderConfiguration::SYSTEM_MODE_CONF_KEY]
  ensure
    set_grader_config("system.mode", "standard")
  end

  test "user_check_in returns JSON heartbeat" do
    sign_in_as("james", "morning")
    post user_check_in_contests_path
    assert_response :success
  end

  # --- finish_open_vivas (the "Finish open vivas" button) ---

  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  def add_viva_to_contest_a
    ContestProblem.create!(contest: contests(:contest_a), problem: problems(:prob_viva), number: 3, enabled: true)
  end

  def open_viva_in_contest_a(answered: true)
    Submission.create!(user: users(:james), problem: problems(:prob_viva), language: viva_language,
                       status: :submitted, submitted_at: Time.zone.now).tap do |sub|
      sub.viva_turns.create!(role: :assistant, status: :ok, content: 'hello')
      sub.viva_turns.create!(role: :student, status: :ok, content: 'answer') if answered
    end
  end

  def finish_open_vivas_audit_rows
    AuditLog.where(auditable_type: 'Contest', auditable_id: contests(:contest_a).id, action: 'finish_open_vivas')
  end

  test "contest page shows the Finish open vivas button only when the contest has a viva problem" do
    sign_in_as("admin", "admin")
    get contest_path(contests(:contest_a))
    assert_response :success
    assert_no_match(/Finish open vivas/, response.body)

    add_viva_to_contest_a
    open_viva_in_contest_a
    get contest_path(contests(:contest_a))
    assert_response :success
    assert_match(/Finish open vivas/, response.body)
    assert_match(/Finish 1 open viva session\?/, response.body)
  end

  test "finish_open_vivas grades answered sessions, archives greeting-only ones, toasts and audits the counts" do
    add_viva_to_contest_a
    answered = open_viva_in_contest_a(answered: true)
    peek     = open_viva_in_contest_a(answered: false)
    sign_in_as("admin", "admin")
    assert_difference -> { finish_open_vivas_audit_rows.count }, 1 do
      assert_enqueued_with(job: Llm::VivaGradeAssistJob) do
        post finish_open_vivas_contest_path(contests(:contest_a)), as: :turbo_stream
      end
    end
    assert_response :success
    assert_match(/Sent 1 session to grading, archived 1 greeting-only session\./, response.body)
    assert_match(/target="open-viva-count"/, response.body, "response must refresh the button's open-count badge")
    assert_predicate answered.reload, :evaluating?
    assert peek.reload.viva_archived_at.present?
    log = finish_open_vivas_audit_rows.last
    assert_equal [nil, 1], log.object_changes['graded_count']
    assert_equal [nil, 1], log.object_changes['archived_count']
    assert_equal [nil, 0], log.object_changes['skipped_count']
  end

  test "finish_open_vivas with nothing open toasts and writes no audit row" do
    add_viva_to_contest_a
    sign_in_as("admin", "admin")
    assert_no_difference -> { AuditLog.count } do
      post finish_open_vivas_contest_path(contests(:contest_a)), as: :turbo_stream
    end
    assert_response :success
    assert_match(/No open viva sessions\./, response.body)
  end

  test "contest editor (mary) can finish open vivas of their own contest" do
    add_viva_to_contest_a
    sign_in_as("mary", "mary")
    post finish_open_vivas_contest_path(contests(:contest_a)), as: :turbo_stream
    assert_response :success
  end

  test "contest editor (mary) cannot finish open vivas of a contest they don't manage" do
    sign_in_as("mary", "mary")
    post finish_open_vivas_contest_path(contests(:contest_b)), as: :turbo_stream
    assert_response :redirect
  end

  test "normal user cannot finish open vivas" do
    sign_in_as("john", "hello")
    post finish_open_vivas_contest_path(contests(:contest_a)), as: :turbo_stream
    assert_response :redirect
  end

  # --- viva grading status line (next to "Finish open vivas") ---

  def viva_session_in_contest_a(status:)
    Submission.create!(user: users(:james), problem: problems(:prob_viva), language: viva_language,
                       status: status, submitted_at: Time.zone.now)
  end

  test "contest page shows All vivas graded when nothing is waiting, with the refresh timer off" do
    add_viva_to_contest_a
    sign_in_as("admin", "admin")
    get contest_path(contests(:contest_a))
    assert_response :success
    assert_select 'turbo-frame#viva-status', 1
    assert_select 'turbo-frame#viva-status .badge', text: 'All vivas graded'
    assert_select 'turbo-frame#viva-status [data-controller=refresh][data-refresh-delay-value="-1"]', 1
  end

  test "viva_status shows the grading and error counts and keeps refreshing while grading" do
    add_viva_to_contest_a
    viva_session_in_contest_a(status: :evaluating)
    viva_session_in_contest_a(status: :evaluating)
    viva_session_in_contest_a(status: :grader_error)
    sign_in_as("admin", "admin")
    get viva_status_contest_path(contests(:contest_a))
    assert_response :success
    assert_select 'turbo-frame#viva-status .badge', text: 'Grading: 2 in progress'
    assert_select 'turbo-frame#viva-status .badge', text: '1 grader error'
    assert_select 'turbo-frame#viva-status [data-refresh-delay-value="10000"]', 1
    assert_select "turbo-frame#viva-status a[href=?][data-refresh-target=refreshLink]", viva_status_contest_path(contests(:contest_a))
  end

  test "viva_status stops refreshing when only grader errors are left" do
    add_viva_to_contest_a
    viva_session_in_contest_a(status: :grader_error)
    sign_in_as("admin", "admin")
    get viva_status_contest_path(contests(:contest_a))
    assert_select 'turbo-frame#viva-status .badge', text: '1 grader error'
    assert_select 'turbo-frame#viva-status [data-refresh-delay-value="-1"]', 1
  end

  test "contest page has no viva status line when the contest has no viva problem" do
    sign_in_as("admin", "admin")
    get contest_path(contests(:contest_a))
    assert_select 'turbo-frame#viva-status', 0
  end

  test "a student cannot read the viva status" do
    add_viva_to_contest_a
    sign_in_as("james", "morning")
    get viva_status_contest_path(contests(:contest_a))
    assert_response :redirect
  end

  # --- Viva check ---

  def retook_in_contest_a
    add_viva_to_contest_a
    problems(:prob_viva).update!(viva_prompt: "# Rubric\n- a (20): x\n- b (80): y\n")
    2.times { open_viva_in_contest_a(answered: true) }
    Submission.where(user: users(:james), problem: problems(:prob_viva)).order(:id).last
  end

  test "viva check lists a student who retook, with the Allow another attempt button" do
    latest = retook_in_contest_a
    sign_in_as("admin", "admin")
    get viva_check_contest_path(contests(:contest_a))
    assert_response :success
    assert_select "turbo-frame#viva-check-report [data-controller~=refresh][data-refresh-delay-value='30000']", 1
    assert_select "turbo-frame#viva-check-report tr.table-warning .badge", text: 'Retook'
    assert_select "form[action=?]", allow_viva_retake_submission_path(latest, contest_id: contests(:contest_a).id)
  end

  test "the Reports dropdown links to Viva check only when the contest has a viva problem" do
    sign_in_as("admin", "admin")
    get contest_path(contests(:contest_a))
    assert_select "a[href=?]", viva_check_contest_path(contests(:contest_a)), 0

    add_viva_to_contest_a
    get contest_path(contests(:contest_a))
    assert_select "a.dropdown-item[href=?]", viva_check_contest_path(contests(:contest_a)), text: 'Viva check'
  end

  test "the contest page badge counts the students who need action" do
    retook_in_contest_a
    sign_in_as("admin", "admin")
    get contest_path(contests(:contest_a))
    assert_select "turbo-frame#viva-status a[href=?]", viva_check_contest_path(contests(:contest_a)), text: '1 to check'
  end

  test "viva check on a contest with no viva problem says so" do
    sign_in_as("admin", "admin")
    get viva_check_contest_path(contests(:contest_a))
    assert_response :success
    assert_match(/This contest has no viva problem/, response.body)
  end

  test "a student cannot open viva check" do
    add_viva_to_contest_a
    sign_in_as("james", "morning")
    get viva_check_contest_path(contests(:contest_a))
    assert_response :redirect
  end

  test "an editor of the contest opens viva check, without grant buttons for a problem they cannot edit" do
    latest = retook_in_contest_a
    sign_in_as("mary", "mary")                     # editor of contest_a; prob_viva is in none of her groups
    get viva_check_contest_path(contests(:contest_a))
    assert_response :success
    assert_select "turbo-frame#viva-check-report tr.table-warning .badge", text: 'Retook'
    assert_select "form[action=?]", allow_viva_retake_submission_path(latest, contest_id: contests(:contest_a).id), 0
  end

  test "in contest mode a contest editor gets the grant button on viva check and the grant succeeds" do
    latest = retook_in_contest_a
    set_grader_config("system.mode", "contest")    # contest editors edit the contest's available problems
    sign_in_as("mary", "mary")                     # editor of contest_a; prob_viva is in none of her groups
    get viva_check_contest_path(contests(:contest_a))
    assert_response :success
    assert_select "form[action=?]", allow_viva_retake_submission_path(latest, contest_id: contests(:contest_a).id), 1

    assert_difference -> { AuditLog.where(action: 'viva_retake_grant').count }, 1 do
      post allow_viva_retake_submission_path(latest, contest_id: contests(:contest_a).id), as: :turbo_stream
    end
    assert_response :success
    assert_match(/<turbo-stream action="replace" target="viva-check-report">/, response.body)
    assert latest.reload.viva_retake_granted_at.present?
    assert_equal users(:mary).id, latest.viva_retake_granted_by_id
  end

  test "Allow another attempt from viva check toasts and re-renders the report" do
    latest = retook_in_contest_a
    sign_in_as("admin", "admin")
    post allow_viva_retake_submission_path(latest, contest_id: contests(:contest_a).id), as: :turbo_stream
    assert_response :success
    assert_match(/<turbo-stream action="append" target="toast-area">/, response.body)
    assert_match(/<turbo-stream action="replace" target="viva-check-report">/, response.body)
    assert latest.reload.viva_retake_granted_at.present?
    # A start was freed (site default 3 a day, one other counted session): the plain notice toast.
    assert_equal 'bg-info-subtle', response.body[/<div class='toast-header py-1 ([^']*)'>/, 1]
  end

  test "a grant with a contest the user cannot manage toasts only" do
    latest = retook_in_contest_a                   # sessions first: james can only submit while contest mode is on
    set_grader_config('system.use_problem_group', 'true')   # group editing rights apply only in group mode
    GroupProblem.create!(group: groups(:group_a), problem: problems(:prob_viva), enabled: true)
    sign_in_as("mary", "mary")                     # editor of contest_a only
    post allow_viva_retake_submission_path(latest, contest_id: contests(:contest_b).id), as: :turbo_stream
    assert_response :success
    assert_match(/<turbo-stream action="append" target="toast-area">/, response.body)
    assert_no_match(/viva-check-report/, response.body)
    assert latest.reload.viva_retake_granted_at.present?
  end
end
