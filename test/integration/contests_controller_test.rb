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

  # --- Contest comments (staff notes; design 2026-11-18) ---

  test "a contest editor adds, edits and deletes a comment, also on a finalized contest" do
    contest = contests(:contest_a)
    contest.update_columns(finalized: true)
    sign_in_as("mary", "mary")   # editor of contest_a

    assert_difference -> { contest.comments.count }, 1 do
      post add_comment_contest_path(contest), params: { body: "Room 403 lost power at **10:15**" }, as: :turbo_stream
    end
    assert_response :success
    comment = contest.comments.last
    assert_equal users(:mary), comment.user
    assert_equal "comment", comment.kind
    assert_match "contest-comments", response.body

    get contest_path(contest)
    assert_select "#contest-comments #contest-comment-#{comment.id} strong", "10:15"
    assert_select "#contest-comments", /mary/

    post update_comment_contest_path(contest), params: { comment_id: comment.id, body: "Resolved: +15 min for the room" }, as: :turbo_stream
    assert_equal "Resolved: +15 min for the room", comment.reload.body

    assert_difference -> { contest.comments.count }, -1 do
      post delete_comment_contest_path(contest), params: { comment_id: comment.id }, as: :turbo_stream
    end
  end

  test "an empty contest comment is refused" do
    sign_in_as("admin", "admin")
    assert_no_difference -> { Comment.count } do
      post add_comment_contest_path(contests(:contest_a)), params: { body: "   " }, as: :turbo_stream
    end
    assert_match "Comment not added", response.body
  end

  test "a contest comment's markup is sanitized" do
    sign_in_as("admin", "admin")
    contest = contests(:contest_a)
    contest.comments.create!(kind: :comment, user: users(:admin), body: "<script>alert(1)</script>ok")
    get contest_path(contest)
    assert_select "#contest-comments script", false
  end

  test "a student cannot add or delete a contest comment" do
    contest = contests(:contest_a)
    comment = contest.comments.create!(kind: :comment, user: users(:admin), body: "staff only")
    sign_in_as("james", "morning")   # a contestant of contest_a
    assert_no_difference -> { Comment.count } do
      post add_comment_contest_path(contest), params: { body: "hi" }, as: :turbo_stream
      post delete_comment_contest_path(contest), params: { comment_id: comment.id }, as: :turbo_stream
    end
    post update_comment_contest_path(contest), params: { comment_id: comment.id, body: "hacked" }, as: :turbo_stream
    assert_equal "staff only", comment.reload.body
  end

  test "a comment of another contest cannot be edited through this contest" do
    sign_in_as("admin", "admin")
    other = Contest.where.not(id: contests(:contest_a).id).first
    comment = other.comments.create!(kind: :comment, user: users(:admin), body: "other contest")
    post update_comment_contest_path(contests(:contest_a)), params: { comment_id: comment.id, body: "moved" }, as: :turbo_stream
    assert_response :not_found
    assert_equal "other contest", comment.reload.body
  end

  # --- Extra time ---

  test "a contest editor sets a student's extra time in seconds" do
    sign_in_as("mary", "mary")   # editor of contest_a
    cu = contests_users(:james_in_contest_a)
    post extra_time_user_contest_path(contests(:contest_a)),
         params: { row_id: cu.id, start_offset: "0", end_offset: "660" }, as: :turbo_stream
    assert_response :success
    assert_equal 660, cu.reload.extra_time_second
    assert_match "0 : 660 seconds", response.body
  end

  test "a cleared extra-time field saves 0, not NULL" do
    sign_in_as("admin", "admin")
    cu = contests_users(:james_in_contest_a)
    cu.update!(extra_time_second: 300)
    post extra_time_user_contest_path(contests(:contest_a)),
         params: { row_id: cu.id, start_offset: "", end_offset: "" }, as: :turbo_stream
    cu.reload
    assert_equal 0, cu.extra_time_second
    assert_equal 0, cu.start_offset_second
  end

  test "a negative extra time is refused with an alert" do
    sign_in_as("admin", "admin")
    cu = contests_users(:james_in_contest_a)
    post extra_time_user_contest_path(contests(:contest_a)),
         params: { row_id: cu.id, start_offset: "0", end_offset: "-60" }, as: :turbo_stream
    assert_equal 0, cu.reload.extra_time_second
    assert_match "Extra time not saved", response.body
  end

  test "an editor cannot set extra time in a contest they don't manage" do
    sign_in_as("mary", "mary")   # editor of contest_a only
    cu = contests_users(:jack_in_contest_b)
    post extra_time_user_contest_path(contests(:contest_b)),
         params: { row_id: cu.id, start_offset: "0", end_offset: "600" }, as: :turbo_stream
    assert_equal 0, cu.reload.extra_time_second
  end

  test "a row of another contest cannot be changed through this contest" do
    sign_in_as("mary", "mary")
    cu = contests_users(:jack_in_contest_b)
    post extra_time_user_contest_path(contests(:contest_a)),
         params: { row_id: cu.id, start_offset: "0", end_offset: "600" }, as: :turbo_stream
    assert_response :not_found
    assert_equal 0, cu.reload.extra_time_second
  end

  test "extra time cannot be changed on a finalized contest" do
    contest = contests(:contest_a)
    contest.update_columns(finalized: true)
    sign_in_as("admin", "admin")
    cu = contests_users(:james_in_contest_a)
    post extra_time_user_contest_path(contest),
         params: { row_id: cu.id, start_offset: "0", end_offset: "600" }, as: :turbo_stream
    assert_equal 0, cu.reload.extra_time_second
  end

  # --- Collection actions ---

  test "admin can change system mode" do
    sign_in_as("admin", "admin")
    post set_system_mode_contests_path, params: { mode: "standard" }
    assert_response :redirect
  end

  # Contest asks IP whitelist ON or OFF with no default; Normal turns it off;
  # the allowed list is never touched (design 2026-11-18, revised 2026-11-19).
  test "contest with the whitelist ON turns it on and normal mode turns it off" do
    set_grader_config("right.whitelist_ip", "10.0.5.0/24, 192.0.2.7/32")
    sign_in_as("admin", "admin")

    assert_difference -> { AuditLog.where(action: "mode_change").count }, 1 do
      post set_system_mode_contests_path, params: { mode: "contest", whitelist: "on" }
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

  test "contest with the whitelist OFF switches the mode and leaves the whitelist off" do
    set_grader_config("right.whitelist_ip", "10.0.5.0/24")
    sign_in_as("admin", "admin")

    post set_system_mode_contests_path, params: { mode: "contest", whitelist: "off" }
    reset_grader_config_cache
    assert_equal "contest", GraderConfiguration[GraderConfiguration::SYSTEM_MODE_CONF_KEY]
    assert_not GraderConfiguration.whitelist_active?
    assert_match "Mode changed to", flash[:notice]
    assert_match "IP whitelist is now off", flash[:notice]
    assert_not AuditLog.where(action: "mode_change").last.object_changes.key?("right.whitelist_ignore")
  ensure
    reset_grader_config_cache
  end

  test "contest without a whitelist choice changes nothing" do
    sign_in_as("admin", "admin")
    mode_before = GraderConfiguration[GraderConfiguration::SYSTEM_MODE_CONF_KEY]

    assert_no_difference -> { AuditLog.where(action: "mode_change").count } do
      post set_system_mode_contests_path, params: { mode: "contest" }
      post set_system_mode_contests_path, params: { mode: "indv-contest", whitelist: "maybe" }
    end
    reset_grader_config_cache
    assert_equal mode_before, GraderConfiguration[GraderConfiguration::SYSTEM_MODE_CONF_KEY]
    assert_not GraderConfiguration.whitelist_active?
    assert_match "choose whether the IP whitelist is ON or OFF", flash[:notice]
  ensure
    reset_grader_config_cache
  end

  test "the Contest button opens a dialog with ON and OFF instead of switching at once" do
    set_grader_config("right.whitelist_ip", "10.0.5.0/24")
    sign_in_as("admin", "admin")
    get contests_path

    assert_select "#contest-mode-button[type=button][data-bs-toggle=modal][data-bs-target='#contest-mode-dialog']"
    assert_select "button[type=submit][name=mode][value=contest]", 0
    assert_select "#contest-mode-dialog form input[type=hidden][name=mode][value=contest]"
    assert_select "#contest-mode-dialog button[type=submit][name=whitelist][value=on]", /IP whitelist ON/
    assert_select "#contest-mode-dialog button[type=submit][name=whitelist][value=off]", /IP whitelist OFF/
    assert_select "#contest-mode-dialog", /Allowed list:\s*10\.0\.5\.0\/24/
  ensure
    reset_grader_config_cache
  end

  test "an empty allowed list is flagged on the mode card, in the dialog and in the notice" do
    set_grader_config("right.whitelist_ip", "")
    sign_in_as("admin", "admin")
    get contests_path
    assert_select "#whitelist-state.bg-danger-subtle", /allowed list is empty/
    assert_select "#contest-mode-dialog .bg-danger-subtle", /allowed list is empty/
    assert_select "#contest-mode-dialog button.btn-outline-danger[value=on]", /blocks every student/

    post set_system_mode_contests_path, params: { mode: "contest", whitelist: "on" }
    assert_match "allowed list is EMPTY", flash[:notice]
  ensure
    reset_grader_config_cache
  end

  test "non-admin cannot change system mode" do
    set_grader_config("system.mode", "standard")
    sign_in_as("mary", "mary")   # a group editor — could flip the site's mode before B4
    post set_system_mode_contests_path, params: { mode: "contest", whitelist: "off" }
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

  test "viva check's student and session links leave the frame on a left-click" do
    latest = retook_in_contest_a
    sign_in_as("admin", "admin")
    get viva_check_contest_path(contests(:contest_a))
    assert_select "turbo-frame#viva-check-report a[href=?][data-turbo='false']", viva_submission_path(latest.id)
    assert_select "turbo-frame#viva-check-report a[href=?][data-turbo='false']",
                  stat_contest_user_admin_path(users(:james).id, contests(:contest_a))
    # only the hidden Refresh link may navigate the frame itself
    assert_select "turbo-frame#viva-check-report a[href]:not([data-turbo='false']):not([data-refresh-target])", 0
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

  test "the contest page links to Viva check even when nothing needs action" do
    add_viva_to_contest_a
    problems(:prob_viva).update!(viva_prompt: "# Rubric\n- a (20): x\n- b (80): y\n")   # an unreadable rubric needs action
    sign_in_as("admin", "admin")
    get contest_path(contests(:contest_a))
    assert_select "turbo-frame#viva-status a[href=?][data-turbo='false']", viva_check_contest_path(contests(:contest_a)), text: 'Viva check'
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

  # --- Problem order ---

  test "moveup moves the bottom problem one row" do
    sign_in_as("admin", "admin")
    c = contests(:contest_a)
    assert_difference -> { AuditLog.where(action: 'move_up').count }, 1 do
      post do_problem_contest_path(c), params: {problem_id: problems(:easy).id, command: 'moveup'}, as: :turbo_stream
    end
    assert_equal 1, c.contests_problems.find_by(problem: problems(:easy)).number
    assert_equal 2, c.contests_problems.find_by(problem: problems(:prob_add)).number
  end

  test "reorder_problems saves the posted order" do
    sign_in_as("admin", "admin")
    c = contests(:contest_a)
    assert_difference -> { AuditLog.where(action: 'reorder_problems').count }, 1 do
      post reorder_problems_contest_path(c), params: {problem_order: "#{problems(:easy).id},#{problems(:prob_add).id}"}, as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, "The problem order was saved."
    assert_equal 1, c.contests_problems.find_by(problem: problems(:easy)).number
    assert_equal 2, c.contests_problems.find_by(problem: problems(:prob_add)).number
  end

  test "reorder_problems with the same order writes no audit row" do
    sign_in_as("admin", "admin")
    c = contests(:contest_a)
    assert_no_difference -> { AuditLog.where(action: 'reorder_problems').count } do
      post reorder_problems_contest_path(c), params: {problem_order: "#{problems(:prob_add).id},#{problems(:easy).id}"}, as: :turbo_stream
    end
    assert_response :success
  end

  test "reorder_problems ignores ids outside the contest" do
    sign_in_as("admin", "admin")
    c = contests(:contest_a)
    post reorder_problems_contest_path(c), params: {problem_order: "#{problems(:hard).id},#{problems(:easy).id}"}, as: :turbo_stream
    assert_response :success
    assert_not c.reload.problems.include?(problems(:hard))
    assert_equal 1, c.contests_problems.find_by(problem: problems(:easy)).number
  end

  test "normal user cannot reorder problems" do
    sign_in_as("john", "hello")
    c = contests(:contest_a)
    post reorder_problems_contest_path(c), params: {problem_order: "#{problems(:easy).id},#{problems(:prob_add).id}"}, as: :turbo_stream
    assert_redirected_to list_main_path
    assert_equal 2, c.contests_problems.find_by(problem: problems(:easy)).number
  end

  test "show_problems_query returns rows in display order with position" do
    sign_in_as("admin", "admin")
    c = contests(:contest_a)
    c.contests_problems.update_all(number: 1)
    post show_problems_query_contest_path(c), as: :json
    assert_response :success
    data = JSON.parse(response.body)['data']
    assert_equal c.contests_problems.order(:id).pluck(:id), data.map { |r| r['id'] }
    assert_equal [1, 2], data.map { |r| r['position'] }
  end

  # --- Outside login (turn off for this contest's students) ---

  test "admin can tick the outside-login box where an outside login exists" do
    sign_in_as("admin", "admin")
    with_outside_login do
      patch contest_path(contests(:contest_a)), params: {contest: {outside_login_off: '1'}}
    end
    assert contests(:contest_a).reload.outside_login_off
  end

  test "a group editor cannot tick it" do
    sign_in_as("mary", "mary")
    with_outside_login do
      patch contest_path(contests(:contest_a)), params: {contest: {outside_login_off: '1', description: 'edited by mary'}}
    end
    # the description is saved, so the request went through and only the param was dropped
    assert_equal 'edited by mary', contests(:contest_a).reload.description
    assert_not contests(:contest_a).outside_login_off
  end

  test "admin can untick it" do
    contests(:contest_a).update!(outside_login_off: true)
    sign_in_as("admin", "admin")
    with_outside_login do
      patch contest_path(contests(:contest_a)), params: {contest: {outside_login_off: '0'}}
    end
    assert_not contests(:contest_a).reload.outside_login_off
  end

  test "a finalized contest shows the box disabled" do
    contests(:contest_a).update_columns(finalized: true, outside_login_off: true)
    sign_in_as("admin", "admin")
    with_outside_login do
      get edit_contest_path(contests(:contest_a))
    end
    assert_select 'input[type=checkbox][name="contest[outside_login_off]"][disabled]'
  end

  test "a group editor sees the box disabled" do
    sign_in_as("mary", "mary")
    with_outside_login do
      get edit_contest_path(contests(:contest_a))
    end
    assert_select 'input[type=checkbox][name="contest[outside_login_off]"][disabled]'
  end

  test "without an outside login the box is ignored and hidden" do
    sign_in_as("admin", "admin")
    without_outside_login do
      patch contest_path(contests(:contest_a)), params: {contest: {outside_login_off: '1'}}
      assert_not contests(:contest_a).reload.outside_login_off
      get edit_contest_path(contests(:contest_a))
      assert_no_match(/login for this contest&#39;s students/, response.body)
      assert_no_match(/login for this contest's students/, response.body)
    end
  end

  test "edit page shows the box and the site switch state" do
    sign_in_as("admin", "admin")
    with_outside_login do
      get edit_contest_path(contests(:contest_a))
    end
    assert_includes response.body, "Turn off CU-net login for this contest&#39;s students until the contest ends"
    assert_includes response.body, "CU-net login is currently ON for the rest of the site."
  end

  test "an admin's clone keeps the setting and audits it" do
    contests(:contest_a).update!(outside_login_off: true)
    sign_in_as("admin", "admin")
    get clone_contest_path(contests(:contest_a))
    clone = Contest.order(:id).last
    assert clone.outside_login_off
    row = AuditLog.where(auditable: clone, action: 'clone').last
    assert_equal [nil, true], row.object_changes['outside_login_off']
  end

  test "an editor's clone of a ticked contest is unticked" do
    contests(:contest_a).update!(outside_login_off: true)
    sign_in_as("mary", "mary")
    get clone_contest_path(contests(:contest_a))
    clone = Contest.order(:id).last
    assert_not_equal contests(:contest_a).id, clone.id
    assert_not clone.outside_login_off
    row = AuditLog.where(auditable: clone, action: 'clone').last
    assert_not row.object_changes.key?('outside_login_off')
  end

  test "show page badge" do
    contests(:contest_a).update!(outside_login_off: true)
    sign_in_as("admin", "admin")
    with_outside_login do
      get contest_path(contests(:contest_a))
    end
    assert_includes response.body, "CU-net off for students"
    without_outside_login do
      get contest_path(contests(:contest_a))
    end
    assert_not_includes response.body, "CU-net off for students"
  end

  test "show page badge is gone once the block has ended" do
    c = contests(:contest_a)
    c.update!(outside_login_off: true)
    sign_in_as("admin", "admin")
    travel_to(c.outside_login_block_ends_at + 1.minute) do
      with_outside_login do
        get contest_path(c)
      end
    end
    assert_not_includes response.body, "CU-net off for students"
  end

  # --- help deduction settings (spec 2026-11-21) ---

  test "a contest editor saves the deduction cap and the spending limit; an out-of-range cap is refused" do
    sign_in_as("mary", "mary")   # editor of contest_a
    c = contests(:contest_a)
    get edit_contest_path(c)
    assert_select "input[name='contest[deduction_cap]']", 1
    assert_select "input[name='contest[assist_spending_limit]']", 1

    patch contest_path(c), params: { contest: { deduction_cap: "30", assist_spending_limit: "150" } }
    c.reload
    assert_equal 30, c.deduction_cap
    assert_equal 150, c.assist_spending_limit

    patch contest_path(c), params: { contest: { deduction_cap: "120" } }
    assert_equal 30, c.reload.deduction_cap
    assert_match "must be in 0..100", response.body

    patch contest_path(c), params: { contest: { deduction_cap: "", assist_spending_limit: "" } }
    c.reload
    assert_nil c.deduction_cap
    assert_nil c.assist_spending_limit
  end

  test "the contest page shows the deduction cap and the spending limit" do
    sign_in_as("admin", "admin")
    c = contests(:contest_a)
    c.update!(deduction_cap: 30)
    get contest_path(c)
    assert_match "30 points per problem", response.body
    assert_match "site setting (100)", response.body
  end

  test "a clone copies the deduction cap and the spending limit" do
    sign_in_as("admin", "admin")
    c = contests(:contest_a)
    c.update!(deduction_cap: 30, assist_spending_limit: 150)
    assert_difference "Contest.count", 1 do
      get clone_contest_path(c)
    end
    copy = Contest.order(:id).last
    assert_equal 30, copy.deduction_cap
    assert_equal 150, copy.assist_spending_limit
  end
end
