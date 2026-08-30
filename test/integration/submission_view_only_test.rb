require "test_helper"

# The submission editor page must show the view-only notice (and no
# submit form) to a reporter on a student-hidden problem, and the normal
# form to users who can submit.
class SubmissionViewOnlyTest < ActionDispatch::IntegrationTest
  setup do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    GroupProblem.create!(problem: problems(:hard), group: groups(:group_a), enabled: false)
  end

  test "reporter on gp-disabled problem: notice shown, no submit form" do
    sign_in_as("reba", "reba")
    get direct_edit_problem_submissions_path(problem_id: problems(:hard).id)
    assert_response :success
    assert_match "not open for your submissions", response.body
    assert_no_match "live_submit", response.body
  end

  test "member on normal problem: submit form shown, no notice" do
    sign_in_as("john", "hello")
    get direct_edit_problem_submissions_path(problem_id: problems(:prob_add).id)
    assert_response :success
    assert_match "live_submit", response.body
    assert_no_match "not open for your submissions", response.body
  end

  test "editor on draft problem: submit form shown (editor test-submit)" do
    sign_in_as("mary", "mary")
    get direct_edit_problem_submissions_path(problem_id: problems(:prob_sub).id)
    assert_response :success
    assert_match "live_submit", response.body
  end
end
