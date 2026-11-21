require "test_helper"

class ContestsAiUsageTest < ActionDispatch::IntegrationTest
  setup { @contest = contests(:contest_a) }

  test "unauthenticated is redirected" do
    get ai_usage_contest_path(@contest)
    assert_redirected_to login_main_path
  end

  test "plain user cannot view" do
    sign_in_as("john", "hello")
    get ai_usage_contest_path(@contest)
    assert_response :redirect
  end

  test "admin sees the AI usage page" do
    sign_in_as("admin", "admin")
    get ai_usage_contest_path(@contest)
    assert_response :success
    assert_select "th", text: "AI time", count: 2
    assert_match "All times are in seconds", response.body
    assert_match "ran after the window closed", response.body
    assert_select "th[data-bs-toggle=tooltip]", text: "p95"
    assert_match "total AI cost", response.body
  end

  test "the summary tiles show tokens in and out, and say grading records none" do
    sub = submissions(:add1_by_james)
    sub.update_columns(submitted_at: 30.minutes.ago)
    sub.viva_turns.create!(role: :assistant, status: :ok, sequence: 1, content: "Q1?",
                           created_at: 30.minutes.ago, token_count_in: 412_345, token_count_out: 1_500)
    sign_in_as("admin", "admin")
    get ai_usage_contest_path(@contest)
    assert_select ".card-body div", text: "412k in · 1.5k out tokens", count: 2   # viva turns + total
    assert_select ".card-body div", text: "tokens not recorded"
  end

  test "editor of the contest sees the page" do
    sign_in_as("mary", "mary")     # mary is editor of group_a and contest_a
    get ai_usage_contest_path(@contest)
    assert_response :success
  end

  test "ai_usage_query returns a data array" do
    sign_in_as("admin", "admin")
    post ai_usage_query_contest_path(@contest)
    assert_response :success
    assert_kind_of Array, response.parsed_body["data"]
  end
end
