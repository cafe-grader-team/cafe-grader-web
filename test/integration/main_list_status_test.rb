require "test_helper"

# The main list carries a hidden per-row status cell — solved / inprogress /
# untried — that drives the client-side status filter (main/list.html.haml,
# GitHub #29), and every grader_comment on the list honours the per-user
# verdict display preference (User#verdict_display, set on the profile page).
class MainListStatusTest < ActionDispatch::IntegrationTest
  setup do
    @sub = submissions(:add1_by_john)
  end

  def grade!(points, comment: "PP--")
    @sub.update_columns(points: points, graded_at: 1.hour.ago,
                        grader_comment: comment,
                        status: Submission.statuses[:done])
  end

  def list_rows
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success
    css_select("#main_table tbody tr")
  end

  def row_for(rows, problem)
    # problem_name renders "_" as "_&ZeroWidthSpace;", so match on the
    # entity-decoded text with the zero-width spaces stripped out.
    row = rows.find { |tr| tr.text.delete("\u200B").include?(problem.full_name) }
    assert row, "no row for #{problem.name}"
    row
  end

  # The status cell is the row's last td (rendered server-side; DataTables
  # hides it client-side only).
  def status_of(tr) = tr.css("td").last.text.strip

  test "a full-score problem is solved, an untouched one untried" do
    grade!(100)
    rows = list_rows
    assert_equal "solved",  status_of(row_for(rows, problems(:prob_add)))
    assert_equal "untried", status_of(row_for(rows, problems(:prob_viva)))
  end

  test "a graded submission below full score is inprogress" do
    grade!(55)
    assert_equal "inprogress", status_of(row_for(list_rows, problems(:prob_add)))
  end

  test "update_self saves the verdict preference and the list renders plain text" do
    grade!(100, comment: "PPPP")
    sign_in_as("john", "hello")

    get list_main_path
    assert_select ".verdict-strip"   # default: tiles

    patch update_self_users_path, params: { user: { verdict_display: "plain" } }
    assert_redirected_to profile_users_path
    assert users(:john).reload.verdict_plain?

    get list_main_path
    assert_select ".verdict-strip", count: 0
    plain = css_select("span.grader-comment.text-break")
    assert plain.any? { |span| span.text.include?("[PPPP]") },
           "expected the plain [PPPP] rendering, got: #{plain.map(&:text).inspect}"
  end
end
