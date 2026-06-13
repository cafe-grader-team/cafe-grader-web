require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  # =============================================================
  # Integration tests for authorization at the HTTP level.
  # These test the FULL request cycle: login → request → response.
  # =============================================================

  # -------------------------------------------------------
  # SECTION 1: Login security
  # -------------------------------------------------------

  test "deactivated user cannot log in" do
    post login_login_path, params: { login: "disabled", password: "disabled" }
    assert_redirected_to login_main_path
  end

  test "single user mode blocks non-admin" do
    set_grader_config("system.single_user_mode", "true")
    sign_in_as("john", "hello")
    get list_main_path
    # should be forced out
    assert_redirected_to login_main_path
  end

  test "single user mode allows admin" do
    set_grader_config("system.single_user_mode", "true")
    sign_in_as("admin", "admin")
    get list_main_path
    assert_response :success
  end

  test "disabled user (enabled=false) is blocked after login" do
    # first enable the user to let them have a session, then disable
    user = users(:john)
    sign_in_as("john", "hello")
    user.update_columns(enabled: false)
    get list_main_path
    assert_redirected_to login_main_path
  end

  # -------------------------------------------------------
  # SECTION 2: Problem access via controller
  # -------------------------------------------------------

  test "standard mode: user can access available problem submission page" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    sign_in_as("john", "hello")

    get direct_edit_problem_submissions_path(problem_id: problems(:prob_add).id)
    assert_response :success
  end

  test "standard mode: user cannot access unavailable problem" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    sign_in_as("john", "hello")

    get direct_edit_problem_submissions_path(problem_id: problems(:prob_sub).id)
    # should be redirected (unauthorized)
    assert_response :redirect
  end

  test "contest mode: contest user can access contest problem" do
    set_grader_config("system.mode", "contest")
    sign_in_as("james", "morning")

    get direct_edit_problem_submissions_path(problem_id: problems(:prob_add).id)
    assert_response :success
  end

  test "contest mode: contest user cannot access problem not in their contest" do
    set_grader_config("system.mode", "contest")
    sign_in_as("james", "morning")  # in contest_a only

    # hard is only in contest_b
    get direct_edit_problem_submissions_path(problem_id: problems(:hard).id)
    assert_response :redirect
  end

  test "contest mode: user not in any contest cannot access any problem" do
    set_grader_config("system.mode", "contest")
    sign_in_as("john", "hello")  # not in any contest

    get direct_edit_problem_submissions_path(problem_id: problems(:prob_add).id)
    assert_response :redirect
  end

  # -------------------------------------------------------
  # SECTION 3: Submission viewing via controller
  # -------------------------------------------------------

  test "user can view own submission" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.user_view_submission", "false")
    sign_in_as("john", "hello")

    get submission_path(submissions(:add1_by_john))
    assert_response :success
  end

  test "user cannot view other's submission when config is off" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.user_view_submission", "false")
    sign_in_as("john", "hello")

    get submission_path(submissions(:add1_by_admin))
    assert_response :redirect  # unauthorized
  end

  test "user can view other's submission when config is on" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.user_view_submission", "true")
    sign_in_as("john", "hello")

    get submission_path(submissions(:add1_by_admin))
    assert_response :success
  end

  test "contest user cannot view other contestant's submission in exam" do
    set_grader_config("system.mode", "contest")
    set_grader_config("right.user_view_submission", "false")
    sign_in_as("james", "morning")

    # james should not see jack's submission (or admin's)
    get submission_path(submissions(:add1_by_admin))
    assert_response :redirect
  end

  # -------------------------------------------------------
  # SECTION 4: Admin-only pages blocked for normal users
  # -------------------------------------------------------

  test "non-admin cannot access user admin" do
    sign_in_as("john", "hello")
    get user_admin_index_path
    assert_redirected_to list_main_path
  end

  test "non-admin cannot access configurations" do
    sign_in_as("john", "hello")
    get grader_configuration_index_path
    assert_redirected_to list_main_path
  end

  test "non-admin non-editor cannot access problems management" do
    sign_in_as("john", "hello")
    get problems_path
    assert_redirected_to list_main_path
  end

  test "non-admin non-editor cannot access contests management" do
    sign_in_as("john", "hello")
    get contests_path
    assert_redirected_to list_main_path
  end

  test "non-admin cannot access reports" do
    sign_in_as("john", "hello")
    get "/report/max_score"
    assert_redirected_to list_main_path
  end

  # -------------------------------------------------------
  # SECTION 5: Group editor access
  # -------------------------------------------------------

  test "group editor can access problems management" do
    sign_in_as("mary", "mary")
    get problems_path
    assert_response :success
  end

  test "group editor can access contests management" do
    sign_in_as("mary", "mary")
    get contests_path
    assert_response :success
  end

  test "group editor can access reports" do
    sign_in_as("mary", "mary")
    get "/report/max_score"
    assert_response :success
  end

  # -------------------------------------------------------
  # SECTION 6: Hall of Fame authorization
  # -------------------------------------------------------

  test "admin can access hall of fame even when disabled" do
    set_grader_config("right.user_hall_of_fame", "false")
    sign_in_as("admin", "admin")
    get problem_hof_report_path
    assert_response :success
  end

  test "normal user can access hall of fame when enabled" do
    set_grader_config("right.user_hall_of_fame", "true")
    sign_in_as("john", "hello")
    get problem_hof_report_path
    assert_response :success
  end

  test "normal user blocked from hall of fame when disabled" do
    set_grader_config("right.user_hall_of_fame", "false")
    sign_in_as("john", "hello")
    get problem_hof_report_path
    assert_redirected_to list_main_path
  end

  test "hall of fame detail respects can_view_problem" do
    set_grader_config("system.mode", "contest")
    set_grader_config("right.user_hall_of_fame", "true")
    sign_in_as("james", "morning")  # in contest_a only

    # prob_add is in contest_a — allowed
    get problem_hof_view_report_path(problems(:prob_add))
    assert_response :success

    # hard is only in contest_b — blocked
    get problem_hof_view_report_path(problems(:hard))
    assert_response :redirect
  end

  test "non-admin cannot access hall of fame recompute" do
    set_grader_config("right.user_hall_of_fame", "true")
    sign_in_as("john", "hello")
    post problem_hof_recompute_report_path
    assert_redirected_to list_main_path
  end

  test "admin can access hall of fame recompute" do
    sign_in_as("admin", "admin")
    post problem_hof_recompute_report_path, as: :turbo_stream
    assert_response :success
  end
end
