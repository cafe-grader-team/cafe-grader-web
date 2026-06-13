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

  test "non-admin cannot change system mode" do
    sign_in_as("mary", "mary")
    post set_system_mode_contests_path, params: { mode: "standard" }
    assert_response :redirect
  end

  test "user_check_in returns JSON heartbeat" do
    sign_in_as("james", "morning")
    post user_check_in_contests_path
    assert_response :success
  end
end
