require "test_helper"

class SubmissionsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get submission_path(submissions(:add1_by_admin))
    assert_redirected_to login_main_path
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

  test "archive_viva redirects to the viva page and archives the session" do
    sign_in_as("admin", "admin")
    sub = make_viva_submission(user: users(:john), status: :done)
    post archive_viva_submission_path(sub)
    assert_redirected_to viva_submission_path(sub)
    assert sub.reload.viva_archived_at.present?
    assert_match(/archived/i, flash[:notice])
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
end
