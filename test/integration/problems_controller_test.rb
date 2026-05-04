require "test_helper"

class ProblemsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get problems_path
    assert_redirected_to login_main_path
  end

  test "normal user is redirected from problems index" do
    sign_in_as("john", "hello")
    get problems_path
    assert_redirected_to list_main_path
  end

  test "admin can access problems index" do
    sign_in_as("admin", "admin")
    get problems_path
    assert_response :success
  end

  test "group editor can access problems index" do
    sign_in_as("mary", "mary")
    get problems_path
    assert_response :success
  end

  # --- Read actions ---

  test "admin can edit problem" do
    sign_in_as("admin", "admin")
    get edit_problem_path(problems(:prob_add))
    assert_response :success
  end

  test "admin can view problem stat" do
    sign_in_as("admin", "admin")
    get stat_problem_path(problems(:prob_add))
    assert_response :success
  end

  test "admin can access manage page" do
    sign_in_as("admin", "admin")
    get manage_problems_path
    assert_response :success
  end

  test "admin can access import form" do
    sign_in_as("admin", "admin")
    get import_problems_path
    assert_response :success
  end

  test "admin can query problem manage as JSON" do
    sign_in_as("admin", "admin")
    post manage_query_problems_path, as: :json
    assert_response :success
  end

  # --- Write actions ---

  test "admin can create problem" do
    sign_in_as("admin", "admin")
    assert_difference "Problem.count" do
      post problems_path, params: {
        problem: { name: "newprob", full_name: "New Problem", full_score: 100 }
      }
    end
  end

  test "admin can quick_create problem" do
    sign_in_as("admin", "admin")
    assert_difference ["Problem.count", "Dataset.count"] do
      post quick_create_problems_path, params: { problem: { name: "qcprob" } }, as: :turbo_stream
    end
    prob = Problem.find_by(name: "qcprob")
    assert prob, "new problem should be persisted"
    assert prob.live_dataset, "new problem should have a live dataset assigned"
    assert_response :success
  end

  test "quick_create with invalid name does not create a problem" do
    sign_in_as("admin", "admin")
    assert_no_difference "Problem.count" do
      # blank name fails Problem validation
      post quick_create_problems_path, params: { problem: { name: "" } }, as: :turbo_stream
    end
    # action still renders 200 with an error toast
    assert_response :success
  end

  test "admin can update problem" do
    sign_in_as("admin", "admin")
    p = problems(:prob_add)
    patch problem_path(p), params: {
      problem: { full_name: "Updated Name", permitted_lang: [] }
    }, as: :turbo_stream
    assert_equal "Updated Name", p.reload.full_name
  end

  test "admin can destroy problem" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_sub)
    assert_difference "Problem.count", -1 do
      delete problem_path(prob)
    end
  end

  # --- Toggle endpoints ---

  test "admin can toggle problem availability" do
    sign_in_as("admin", "admin")
    p = problems(:prob_add)
    was = p.available
    post toggle_available_problem_path(p), as: :turbo_stream
    assert_equal !was, p.reload.available
  end

  test "group editor cannot toggle availability (admin only)" do
    sign_in_as("mary", "mary")
    p = problems(:prob_add)
    post toggle_available_problem_path(p), as: :turbo_stream
    # admin_authorization redirects non-admins
    assert_response :redirect
  end

  test "admin can toggle view_testcase" do
    sign_in_as("admin", "admin")
    p = problems(:prob_add)
    was = p.view_testcase
    post toggle_view_testcase_problem_path(p), as: :turbo_stream
    assert_equal !was, p.reload.view_testcase
  end

  # --- Bulk actions (admin only) ---

  test "admin can turn all problems off" do
    sign_in_as("admin", "admin")
    Problem.update_all(available: true)
    get turn_all_off_problems_path
    assert Problem.where(available: true).count == 0
  end

  test "admin can turn all problems on" do
    sign_in_as("admin", "admin")
    Problem.update_all(available: false)
    get turn_all_on_problems_path
    assert Problem.where(available: false).count == 0
  end

  test "non-admin cannot turn all problems off" do
    sign_in_as("mary", "mary")
    get turn_all_off_problems_path
    assert_response :redirect
  end
end
