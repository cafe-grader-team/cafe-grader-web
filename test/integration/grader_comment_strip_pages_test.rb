require "test_helper"

# Every page that shows Submission#grader_comment draws it through
# GraderCommentHelper#grader_comment_strip (the main list is covered by
# main_list_viva_row_test; the submission report renders client-side).
class GraderCommentStripPagesTest < ActionDispatch::IntegrationTest
  setup do
    @sub = submissions(:add1_by_admin)
    @sub.update_columns(status: Submission.statuses[:done], graded_at: 1.hour.ago, points: 50, grader_comment: "P[PP-]")
    sign_in_as("admin", "admin")
  end

  test "submission detail" do
    get submission_path(@sub)
    assert_response :success
    assert_select ".verdict-strip[data-comment='P[PP-]'] .verdict-tile", count: 4
    assert_select ".verdict-strip[data-comment='P[PP-]'] .verdict-group", count: 1
  end

  test "problem statistics keep DataTables order/search on the raw string" do
    get stat_problem_path(@sub.problem)
    assert_response :success
    assert_select "td[data-order='P[PP-]'][data-search='P[PP-]'] .verdict-strip", count: 1
  end

  test "user statistics keep DataTables order/search on the raw string" do
    get stat_user_admin_path(@sub.user)
    assert_response :success
    assert_select "td[data-order='P[PP-]'][data-search='P[PP-]'] .verdict-strip", count: 1
  end

  test "grader monitor" do
    get grader_processes_path
    assert_response :success
    assert_select ".verdict-strip[data-comment='P[PP-]']", minimum: 1
  end

  test "submission report embeds the client-side strip config" do
    get submission_report_path
    assert_response :success
    assert_includes response.body, "cafe.verdictStrip(data, VERDICT_STRIP)"
    assert_match(/const VERDICT_STRIP = \{"codes":\{"\?":\{"result":"waiting"/, response.body)
  end
end
