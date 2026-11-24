require "test_helper"

class SubmissionsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get submission_path(submissions(:add1_by_admin))
    assert_redirected_to_login
  end

  test "user can view own submission" do
    sign_in_as("admin", "admin")
    get submission_path(submissions(:add1_by_admin))
    assert_response :success
  end

  test "user can list submissions by problem" do
    sign_in_as("admin", "admin")
    get problem_submissions_path(problem_id: problems(:prob_add).id)
    assert_response :success
  end

  test "user can download own submission" do
    sign_in_as("admin", "admin")
    get download_submission_path(submissions(:add1_by_admin))
    assert_response :success
  end

  # --- Permissions on rejudge ---

  test "normal user cannot rejudge" do
    sign_in_as("john", "hello")
    sub = submissions(:add1_by_admin)
    post rejudge_submission_path(sub)
    assert_redirected_to list_main_path
  end

  test "admin can rejudge" do
    sign_in_as("admin", "admin")
    sub = submissions(:add1_by_admin)
    post rejudge_submission_path(sub), as: :turbo_stream
    assert_response :success
  end

  # --- Direct edit ---

  test "user can access direct edit for viewable problem" do
    sign_in_as("john", "hello")
    prob = problems(:prob_add)
    get direct_edit_problem_submissions_path(problem_id: prob.id)
    assert_response :success
  end

  # --- Show modals ---

  test "admin can view compiler message modal" do
    sign_in_as("admin", "admin")
    sub = submissions(:add1_by_admin)
    post compiler_msg_submission_path(sub), as: :turbo_stream
    assert_response :success
  end

  test "admin can view evaluations modal" do
    sign_in_as("admin", "admin")
    sub = submissions(:add1_by_admin)
    post evaluations_submission_path(sub), as: :turbo_stream
    assert_response :success
  end

  test "non-owner cannot view another user's compiler message" do
    sign_in_as("john", "hello")
    sub = submissions(:sub1_by_admin)
    post compiler_msg_submission_path(sub), as: :turbo_stream
    assert_response :redirect
  end

  # --- set_tag (admin can mutate) ---

  test "normal user cannot set tag on others' submission" do
    sign_in_as("john", "hello")
    sub = submissions(:add1_by_admin)
    get set_tag_submission_path(sub), params: { tag: "x" }
    assert_response :redirect
  end

  # --- viva editor guard + archive redirect (smoke-test UX fixes) ---

  # `viva` Language isn't in fixtures — find_or_create_by! so this works
  # whether or not another test already seeded it within this run.
  def viva_language
    Language.find_or_create_by!(name: 'viva') { |l| l.pretty_name = 'Viva Exam' }
  end

  def make_viva_submission(user:, status:)
    Submission.create!(user: user, problem: problems(:prob_viva), language: viva_language,
                        status: status, submitted_at: Time.zone.now)
  end

  test "GET edit on a viva submission redirects to the viva page, not the code editor" do
    sign_in_as("john", "hello")
    sub = make_viva_submission(user: users(:john), status: :submitted)
    get edit_submission_path(sub)
    assert_redirected_to viva_submission_path(sub)
  end

  test "direct_edit_problem on a viva problem redirects to the problem list, not the code editor" do
    sign_in_as("john", "hello")
    get direct_edit_problem_submissions_path(problem_id: problems(:prob_viva).id)
    assert_redirected_to list_main_path
    assert_match(/Start Viva/, flash[:alert])
  end

  def retake_audit_rows
    AuditLog.where(action: 'viva_retake_grant')
  end

  test "allow_viva_retake archives an open session, stops it counting, audits and redirects to the viva page" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :submitted)
    assert_difference -> { retake_audit_rows.count }, 1 do
      post allow_viva_retake_submission_path(sub)
    end
    assert_redirected_to viva_submission_path(sub)
    sub.reload
    assert sub.viva_archived_at.present?
    assert sub.viva_retake_granted_at.present?
    assert_equal users(:admin).id, sub.viva_retake_granted_by_id
    assert_match(/another attempt/i, flash[:notice])
    log = retake_audit_rows.last
    assert_equal ['Problem', sub.problem_id], [log.auditable_type, log.auditable_id]
    assert_equal [nil, sub.id], log.object_changes['submission_id']
    assert_equal [nil, 'john'], log.object_changes['user']
  end

  test "allow_viva_retake a second time changes nothing and says so" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :done)
    sub.grant_viva_retake!(by: users(:admin))
    assert_no_difference -> { retake_audit_rows.count } do
      post allow_viva_retake_submission_path(sub)
    end
    assert_redirected_to viva_submission_path(sub)
    assert_match(/already/i, flash[:alert])
  end

  # The grant message says what the student can do now (Viva::StartPolicy read
  # after the grant), not just that the session was freed.
  def answered_viva_submission(user:, status: :done)
    make_viva_submission(user: user, status: status).tap do |sub|
      sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    end
  end

  test "allow_viva_retake on the student's only counted session says they may start again, with the starts left" do
    problems(:prob_viva).update!(viva_daily_limit: 1)
    sub = answered_viva_submission(user: users(:john))
    sign_in_as("admin", "admin")
    post allow_viva_retake_submission_path(sub)
    assert_equal "Session ##{sub.id} is closed and no longer counts toward the start limit. " \
                 "john may start another attempt at '#{problems(:prob_viva).name}' (1 start left today).",
                 flash[:notice]
    assert_nil flash[:alert]
  end

  test "allow_viva_retake when another answered session today still counts says no start is left" do
    problems(:prob_viva).update!(viva_daily_limit: 1)
    answered_viva_submission(user: users(:john))
    latest = answered_viva_submission(user: users(:john))
    sign_in_as("admin", "admin")
    post allow_viva_retake_submission_path(latest, contest_id: contests(:contest_a).id), as: :turbo_stream
    assert_response :success
    assert latest.reload.viva_retake_granted_at.present?
    toast = "Session ##{latest.id} is closed and no longer counts toward the start limit, but john still has no " \
            'start left today: another answered session of theirs today still counts. ' \
            'Use Allow another attempt on that session too if they should start again.'
    assert_includes response.body, toast
    # No start was freed: a warning toast, so staff notice "grant that one too".
    toast_style = response.body[/<div class='toast-header py-1 ([^']*)'>/, 1]
    assert_equal 'bg-warning-subtle', toast_style

    # A second click says the same, after "already has a grant".
    post allow_viva_retake_submission_path(latest)
    assert_match(/\ASession ##{latest.id} already has a grant\. It is closed .*but john still has no start left today/,
                 flash[:alert])
  end

  test "allow_viva_retake on a contest-only viva outside contest mode says it can start only during a contest, as an alert" do
    problems(:prob_viva).update!(viva_daily_limit: 0)
    sub = answered_viva_submission(user: users(:john))
    sign_in_as("admin", "admin")
    post allow_viva_retake_submission_path(sub)
    assert sub.reload.viva_retake_granted_at.present?, 'the grant itself still happens'
    # No start was freed, so the session page shows it in the alert style.
    assert_nil flash[:notice]
    assert_equal "Session ##{sub.id} is closed and no longer counts toward the start limit, " \
                 'but this viva can be started only during a contest.', flash[:alert]
  end

  test "a student cannot allow another attempt" do
    sign_in_as("john", "hello")
    sub = make_viva_submission(user: users(:john), status: :done)
    post allow_viva_retake_submission_path(sub)
    assert_nil sub.reload.viva_retake_granted_at
  end

  test "an editor of the problem's group can allow another attempt" do
    set_grader_config('system.use_problem_group', 'true')
    GroupProblem.create!(group: groups(:group_a), problem: problems(:prob_viva), enabled: true)
    sign_in_as("mary", "mary")
    sub = make_viva_submission(user: users(:john), status: :done)
    post allow_viva_retake_submission_path(sub)
    assert sub.reload.viva_retake_granted_at.present?
  end

  test "the viva page offers Allow another attempt to staff" do
    sub = make_viva_submission(user: users(:john), status: :submitted)
    sign_in_as("admin", "admin")
    get viva_submission_path(sub)
    assert_response :success
    assert_select "form[action=?]", allow_viva_retake_submission_path(sub)
    assert_no_match(/Archive &amp; allow retake/, response.body)
  end

  test "the viva page does not offer Allow another attempt to the student" do
    sub = make_viva_submission(user: users(:john), status: :submitted)
    sign_in_as("john", "hello")
    get viva_submission_path(sub)
    assert_response :success
    assert_select "form[action=?]", allow_viva_retake_submission_path(sub), 0
  end

  # Reachable via the ballot link in _submission_short.html.haml on any
  # graded viva. Pre-fix this 500'd with NoMethodError, since a viva
  # submission's problem has no live_dataset to call #testcases on.
  test "evaluations on a viva submission redirects to the viva page, not a 500" do
    sign_in_as("john", "hello")
    sub = make_viva_submission(user: users(:john), status: :done)
    post evaluations_submission_path(sub), as: :turbo_stream
    assert_redirected_to viva_submission_path(sub)
  end

  test "download on a viva submission redirects to the viva page, not a nil-source send" do
    sign_in_as("john", "hello")
    sub = make_viva_submission(user: users(:john), status: :done)
    get download_submission_path(sub)
    assert_redirected_to viva_submission_path(sub)
  end

  # A submission that Submission.fail_stale_viva_evaluating! swept to
  # :grader_error (worker crashed mid-grade-call) must be regradable through
  # the ordinary admin rejudge path — see rejudge above, which special-cases
  # problem.viva_exam? regardless of the submission's current status.
  test "a submission swept to grader_error by the stale-evaluating sweeper can be regraded via rejudge" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :evaluating)
    sub.update_columns(updated_at: 21.minutes.ago)

    assert_equal 1, Submission.fail_stale_viva_evaluating!
    assert_predicate sub.reload, :grader_error?

    post rejudge_submission_path(sub), as: :turbo_stream
    assert_response :success
    assert_predicate sub.reload, :evaluating?
  end

  # --- grade history: rejudge options + adopt_viva_grade (spec 2026-09-23-viva-grade-history-design) ---

  def make_run(sub, total:, superseded_at: nil, reason: nil)
    sub.viva_grades.create!(total_points: total, narrative: "n#{total}", score_json: {'a' => total}.to_json,
                            llm_model: 'test-model', graded_at: Time.zone.now, superseded_at: superseded_at,
                            superseded_reason: reason)
  end

  test "viva rejudge passes the model, the never-lower choice and the admin to the job and keeps the grade" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :done)
    make_run(sub, total: 40)
    sub.update!(points: 40)
    assert_enqueued_with(job: Llm::VivaGradeAssistJob,
                         args: [sub, {model: 'gemini-x', never_lower: false, requested_by_id: users(:admin).id}]) do
      post rejudge_submission_path(sub), params: {model: 'gemini-x', never_lower: '0'}, as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, 'replaces the current grade'
    sub.reload
    assert_equal 'done', sub.status
    assert_equal 40, sub.points
    assert_equal 1, sub.viva_grades.count, 'the old row is kept, not destroyed'
  end

  test "viva rejudge keeps the higher grade when the box is ticked and retries a failed first grading" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :grader_error)
    assert_enqueued_with(job: Llm::VivaGradeAssistJob, args: [sub, {never_lower: true, requested_by_id: users(:admin).id}]) do
      post rejudge_submission_path(sub), params: {model: '', never_lower: '1'}, as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, 'keeps the higher grade'
    assert_predicate sub.reload, :evaluating?
  end

  test "viva rejudge on an open interview is refused with an alert toast" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :submitted)
    assert_no_enqueued_jobs(only: Llm::VivaGradeAssistJob) do
      post rejudge_submission_path(sub), params: {never_lower: '1'}, as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, 'still open'
    assert_predicate sub.reload, :submitted?
  end

  test "adopt_viva_grade makes an earlier run current, audits it and redirects to the viva page" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :done)
    old = make_run(sub, total: 40, superseded_at: 1.hour.ago, reason: 'replaced')
    cur = make_run(sub, total: 70)
    sub.update!(points: 70)
    post adopt_viva_grade_submission_path(sub, grade_id: old.id)
    assert_redirected_to viva_submission_path(sub)
    follow_redirect!
    assert_includes response.body, 'is now the current grade'
    sub.reload
    assert_equal 40, sub.points
    assert_equal old, sub.viva_grade
    assert_equal 'reverted', cur.reload.superseded_reason
    audit = AuditLog.where(auditable: sub.problem, action: 'viva_grade_adopt').order(:id).last
    assert_equal [cur.id, old.id], audit.object_changes['grade_id']
    assert_equal [70.0, 40.0], audit.object_changes['points']
    assert_equal users(:admin).id, audit.user_id
  end

  test "adopt_viva_grade refuses a grade run of another session" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :done)
    make_run(sub, total: 70)
    sub.update!(points: 70)
    other = make_viva_submission(user: users(:james), status: :done)
    foreign = make_run(other, total: 90, superseded_at: 1.hour.ago, reason: 'replaced')
    post adopt_viva_grade_submission_path(sub, grade_id: foreign.id)
    assert_redirected_to viva_submission_path(sub)
    assert_equal 'No such grade run for this session.', flash[:alert]
    assert_equal 70, sub.reload.points
    assert_nil foreign.reload.superseded_by_id
    refute AuditLog.where(action: 'viva_grade_adopt').exists?
  end

  test "adopt_viva_grade refuses a failed run and a session still grading" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :done)
    make_run(sub, total: 70)
    sub.update!(points: 70)
    failed = sub.viva_grades.create!(superseded_at: Time.zone.now, superseded_reason: 'error', error: 'x')
    post adopt_viva_grade_submission_path(sub, grade_id: failed.id)
    assert_redirected_to viva_submission_path(sub)
    assert_match(/produced no grade/, flash[:alert])
    assert_equal 70, sub.reload.points

    old = make_run(sub, total: 40, superseded_at: 1.hour.ago, reason: 'replaced')
    sub.update!(status: :evaluating)
    post adopt_viva_grade_submission_path(sub, grade_id: old.id)
    assert_redirected_to viva_submission_path(sub)
    assert_match(/in progress/, flash[:alert])
    assert_equal 70, sub.reload.points
  end

  test "a normal user cannot adopt a viva grade" do
    sign_in_as("john", "hello")
    sub = make_viva_submission(user: users(:john), status: :done)
    run = make_run(sub, total: 40, superseded_at: 1.hour.ago, reason: 'replaced')
    post adopt_viva_grade_submission_path(sub, grade_id: run.id)
    assert_redirected_to list_main_path
  end

  # --- My Submissions, all problems (issue #62) ---

  # save!(validate: false) keeps the model's number callback and skips the
  # submit-right validation (the way trusted tooling creates rows); every
  # test below asserts on the row's "#id" link, which only the table prints.
  def make_submission(user:, problem:, submitted_at: Time.zone.now)
    s = Submission.new(user: user, problem: problem, language: languages(:Language_c),
                       submitted_at: submitted_at, source: "int main(){}")
    s.save!(validate: false)
    s
  end

  test "index without a problem lists the student's submissions across problems, newest first" do
    sign_in_as("james", "morning")
    older  = submissions(:add1_by_james)   # prob_add, available
    hidden = submissions(:sub1_by_james)   # prob_sub is unavailable: the student cannot open it
    newer  = make_submission(user: users(:james), problem: problems(:easy))

    get submissions_path
    assert_response :success
    assert_select "th", text: "Problem"
    assert_match "##{newer.id}", response.body
    assert_match "##{older.id}", response.body
    assert_no_match "##{hidden.id}", response.body
    assert_operator response.body.index("##{newer.id}"), :<, response.body.index("##{older.id}")
    assert_match problems(:easy).full_name, response.body
    assert_match problems(:prob_add).full_name, response.body
  end

  test "index for one problem keeps the per-problem layout and links back to all problems" do
    sign_in_as("james", "morning")
    get problem_submissions_path(problems(:prob_add))
    assert_response :success
    assert_select "th", text: "Problem", count: 0
    assert_select "a[href=?]", submissions_path, text: /All problems/
  end

  test "index without a problem for an admin lists their submissions on every problem" do
    sign_in_as("admin", "admin")
    get submissions_path
    assert_response :success
    assert_match "##{submissions(:add1_by_admin).id}", response.body
    assert_match "##{submissions(:sub1_by_admin).id}", response.body   # unavailable problem; an admin may open it
  end

  test "index pages the list 50 at a time and clamps an out-of-range page" do
    sign_in_as("james", "morning")
    now = Time.zone.now
    Submission.insert_all((1..60).map { |n|
      { user_id: users(:james).id, problem_id: problems(:easy).id, language_id: languages(:Language_c).id,
        submitted_at: now - (60 - n).minutes, number: n, source: "int main(){}" }
    })
    # 60 new rows + add1_by_james = 61 visible (sub1_by_james is on an unavailable problem)

    get submissions_path
    assert_select "tbody tr", 50
    assert_match "Page 1 of 2 (61 submissions)", response.body
    assert_select "a.page-link[href=?]", submissions_path(page: 2), text: /Older/

    get submissions_path(page: 2)
    assert_select "tbody tr", 11
    assert_match "##{submissions(:add1_by_james).id}", response.body   # the oldest row lands on the last page

    get submissions_path(page: 99)
    assert_match "Page 2 of 2", response.body
  end

  test "index in contest mode lists only submissions made inside the active contests' window" do
    sign_in_as("john", "hello")
    contest = contests(:contest_a)   # started 1 hour ago, stops in 3 hours
    ContestProblem.create!(contest: contest, problem: problems(:prob_add), number: 1, enabled: true)
    ContestUser.create!(contest: contest, user: users(:john), role: 0, enabled: true,
                        start_offset_second: 0, extra_time_second: 0)
    set_grader_config("system.mode", "contest")
    inside = make_submission(user: users(:john), problem: problems(:prob_add), submitted_at: 10.minutes.ago)
    before = submissions(:add1_by_john)   # submitted in 2019, long before the contest

    get submissions_path
    assert_response :success
    assert_match "##{inside.id}", response.body
    assert_no_match "##{before.id}", response.body
  ensure
    set_grader_config("system.mode", "standard")
  end

  # --- Compiler message (GitHub #50 follow-up) ---
  # Compilers echo source lines, so a student can plant markup in a single
  # `#error` line; staff open the message, so it must render as text.

  COMPILER_XSS = "main.cpp:1: error: #error <img src=x onerror=alert(1)>"

  test "compiler message modal shows the compiler output as text" do
    sub = submissions(:add1_by_john)
    sub.update_columns(compiler_message: COMPILER_XSS)
    sign_in_as("admin", "admin")
    post compiler_msg_submission_path(sub), as: :turbo_stream
    assert_response :success
    assert_no_match(/<img/, response.body)
    assert_includes response.body, "<pre>main.cpp:1: error: #error &lt;img src=x onerror=alert(1)&gt;</pre>"
  end

  test "submission page embeds the compiler message as text" do
    sub = submissions(:add1_by_john)
    sub.update_columns(compiler_message: COMPILER_XSS)
    sign_in_as("admin", "admin")
    get submission_path(sub)
    assert_response :success
    modal = css_select("#compiler-msg-modal").first.to_html
    assert_no_match(/<img/, modal)
    assert_includes modal, "<pre>main.cpp:1: error: #error &lt;img src=x onerror=alert(1)&gt;</pre>"
  end
end
