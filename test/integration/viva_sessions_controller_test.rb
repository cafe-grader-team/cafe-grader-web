require "test_helper"

class VivaSessionsControllerTest < ActionDispatch::IntegrationTest
  # `viva_sessions#start` requires both:
  #   - a problem with mode=:viva_exam
  #   - a Language with name='viva' (seeded; not in fixtures)
  # We test the failure paths plus the basic auth boundary.

  setup do
    @owner_sub = submissions(:add1_by_john)         # owned by `john`
    @other_sub = submissions(:add1_by_admin)        # owned by admin (john not the owner)
  end

  # --- Authorization on show ---

  test "unauthenticated cannot view viva session" do
    get viva_submission_path(@owner_sub)
    assert_redirected_to login_main_path
  end

  test "owner can view their viva session" do
    sign_in_as("john", "hello")
    get viva_submission_path(@owner_sub)
    # show has no explicit owner check — the view just renders viva_turns.
    # That's questionable, but it's the current behavior; we document it.
    assert_response :success
  end

  test "admin can view any viva session" do
    sign_in_as("admin", "admin")
    get viva_submission_path(@other_sub)
    assert_response :success
  end

  # --- answer enforces ownership ---

  test "non-owner cannot answer in another user's viva session" do
    sign_in_as("john", "hello")
    post viva_answer_submission_path(@other_sub), params: { content: "hi" }
    assert_redirected_to list_main_path
  end

  test "owner gets validation error when answering with empty content" do
    sign_in_as("john", "hello")
    post viva_answer_submission_path(@owner_sub), params: { content: "   " }
    assert_response :redirect # redirect to viva path with alert
  end

  # --- start failure paths ---

  test "start redirects when problem is not a viva exam" do
    sign_in_as("admin", "admin")
    # prob_add has mode default (general), not viva_exam
    post viva_start_problem_path(problems(:prob_add))
    assert_redirected_to list_main_path
  end
end
