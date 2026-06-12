require "test_helper"

# Covers the activity report (per-user submission summary).
# The older reports (max_score / submission / login) predate this file
# and are still untested — extend here when touching them.
class ReportControllerTest < ActionDispatch::IntegrationTest
  # all submission fixtures are submitted_at 2019-10-22
  RANGE = { use: "time", from_time: "2019-01-01 00:00", to_time: "2020-12-31 00:00" }.freeze

  def activity_params(extra = {})
    { sub_range: RANGE, probs: { use: "all" }, users: { use: "all" } }.merge(extra)
  end

  def query_rows(extra = {})
    post activity_query_report_path(format: :json), params: activity_params(extra)
    assert_response :success
    response.parsed_body["data"].index_by { |r| r["login"] }
  end

  # --- authorization ---

  test "unauthenticated cannot view activity report" do
    get activity_report_path
    assert_redirected_to login_main_path
  end

  test "regular user cannot view activity report" do
    sign_in_as("john", "hello")
    get activity_report_path
    assert_response :redirect
  end

  test "regular user cannot post activity_query" do
    sign_in_as("john", "hello")
    post activity_query_report_path(format: :json), params: activity_params
    assert_response :redirect
  end

  # --- aggregation ---

  test "admin can view activity report page" do
    sign_in_as("admin", "admin")
    get activity_report_path
    assert_response :success
  end

  test "activity_query aggregates submissions per user" do
    sign_in_as("admin", "admin")
    rows = query_rows

    assert_equal 2, rows["admin"]["sub_count"]   # add1_by_admin + sub1_by_admin
    assert_equal 2, rows["admin"]["prob_count"]
    assert_equal 0, rows["admin"]["solved_count"] # no fixture has points
    assert_equal 1, rows["john"]["sub_count"]
    assert_equal 2, rows["james"]["sub_count"]
    assert_not_nil rows["admin"]["first_sub"]
    assert_nil rows["mary"], "users with no submissions must be hidden by default"
  end

  test "solved counts 100-point submissions but excludes raw_sum-scored problems" do
    submissions(:add1_by_john).update_columns(points: 100)   # sum-scored -> solved
    submissions(:sub1_by_james).update_columns(points: 100)  # will become raw_sum -> excluded
    datasets(:ds_sub).update_columns(score_type: Dataset.score_types[:raw_sum])

    sign_in_as("admin", "admin")
    rows = query_rows

    assert_equal 1, rows["john"]["solved_count"]
    assert_equal 0, rows["james"]["solved_count"],
      "100 points on a raw_sum problem must not count as solved"
    assert_equal 2, rows["james"]["prob_count"], "raw_sum problems still count as tried"
  end

  test "time range excludes submissions outside it" do
    sign_in_as("admin", "admin")
    rows = query_rows(sub_range: { use: "time", from_time: "2030-01-01 00:00", to_time: "2030-12-31 00:00" })
    assert_empty rows
  end

  test "show_inactive appends zero rows for selected users" do
    sign_in_as("admin", "admin")
    rows = query_rows(show_inactive: "true")

    assert_not_nil rows["mary"]
    assert_equal 0, rows["mary"]["sub_count"]
    assert_nil rows["mary"]["first_sub"]
    assert_equal 2, rows["admin"]["sub_count"], "active rows unaffected by show_inactive"
  end
end
