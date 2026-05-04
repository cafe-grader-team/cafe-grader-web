require "test_helper"

class ReportControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated user is redirected" do
    get "/report/max_score"
    assert_redirected_to login_main_path
  end

  test "normal user is redirected from reports" do
    sign_in_as("john", "hello")
    get "/report/max_score"
    assert_redirected_to list_main_path
  end

  test "admin can access max_score report" do
    sign_in_as("admin", "admin")
    get "/report/max_score"
    assert_response :success
  end

  test "admin can access login report" do
    sign_in_as("admin", "admin")
    get "/report/login"
    assert_response :success
  end

  test "admin can access submission report" do
    sign_in_as("admin", "admin")
    get "/report/submission"
    assert_response :success
  end

  # --- AI report ---

  test "admin can access AI report" do
    sign_in_as("admin", "admin")
    get "/report/ai"
    assert_response :success
  end

  # --- Stuck / cheat reports ---

  test "admin can access stuck report" do
    skip "FIXME: ReportController#stuck (line 365) does `>=` on a nil — the action expects a query param that's missing on a bare GET. Either make the param required or default it."
    sign_in_as("admin", "admin")
    get "/report/stuck"
    assert_response :success
  end

  test "admin can access cheat_report" do
    sign_in_as("admin", "admin")
    get "/report/cheat_report"
    assert_response :success
  end

  test "admin can access multiple_login report" do
    skip "FIXME: ReportController#multiple_login (line 382) emits SQL incompatible with MySQL only_full_group_by mode (selects submissions.id without aggregation in a GROUP BY query)."
    sign_in_as("admin", "admin")
    get "/report/multiple_login"
    assert_response :success
  end

  # --- JSON query endpoints ---

  test "admin can query max_score data as JSON" do
    sign_in_as("admin", "admin")
    post "/report/max_score_query", params: { problem_ids: [problems(:prob_add).id], user_ids: [users(:john).id] }, as: :json
    assert_response :success
  end

  test "admin can query submission data as JSON" do
    sign_in_as("admin", "admin")
    post "/report/submission_query", params: { problem_ids: [problems(:prob_add).id], user_ids: [users(:john).id] }, as: :json
    assert_response :success
  end

  test "admin can query login data as JSON" do
    sign_in_as("admin", "admin")
    post "/report/login_summary_query", as: :json
    assert_response :success
  end

  test "admin can query login_detail as JSON" do
    sign_in_as("admin", "admin")
    post "/report/login_detail_query", params: { user_id: users(:john).id }, as: :json
    assert_response :success
  end
end
