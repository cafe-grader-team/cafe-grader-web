require "test_helper"

# The student main list renders each problem's latest submission through
# application/_submission_short. A viva row must show a marker badge that
# links to the viva page — never the LLM narrative (which lives on
# viva_grade) and never the per-testcase evaluations / compiler-msg links.
class MainListVivaRowTest < ActionDispatch::IntegrationTest
  NARRATIVE = 'Your performance in this viva was outstanding. You demonstrated an exceptional grasp of the material.'

  setup do
    @viva = problems(:prob_viva)
    @sub  = Submission.new(user: users(:john), problem: @viva, language: languages(:Language_c),
                           source: 'viva', submitted_at: 2.hours.ago, number: 1)
  end

  def save_viva_sub!(status:, graded_at:, grader_comment:, **attrs)
    @sub.assign_attributes(status: status, graded_at: graded_at, grader_comment: grader_comment, **attrs)
    @sub.save!(validate: false)
  end

  def graded!(terminated: false, grader_comment: Submission::VIVA_RESULT_MARKER)
    save_viva_sub!(status: :done, graded_at: 1.hour.ago, points: 100, grader_comment: grader_comment,
                   viva_terminated_at: (1.hour.ago if terminated))
    VivaGrade.create!(submission: @sub, total_points: 100, narrative: NARRATIVE)
  end

  # The <tr> of the viva problem on the rendered list (other rows — e.g. the
  # ungraded add1_by_john fixture — legitimately say "Waiting to be graded").
  def viva_row
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success
    row = css_select("#main_table tbody tr").find { |tr| tr.to_s.include?(@viva.full_name) }
    assert row, "viva problem row not rendered"
    row
  end

  test "graded viva row shows the viva badge linking to the viva page and no narrative" do
    graded!
    row = viva_row
    assert_select row, "a.badge[href=?]", viva_submission_path(@sub), text: /viva/
    assert_select row, "a[href=?]", evaluations_submission_path(@sub), count: 0
    assert_select row, "a[href=?]", compiler_msg_submission_path(@sub), count: 0
    refute_includes response.body, NARRATIVE
  end

  test "terminated viva row shows the terminated badge" do
    graded!(terminated: true)
    assert_select viva_row, "a.badge[href=?]", viva_submission_path(@sub), text: /terminated/
  end

  test "a legacy row whose grader_comment still holds the narrative does not leak it" do
    graded!(grader_comment: NARRATIVE)   # pre-cleanup data shape
    viva_row
    refute_includes response.body, NARRATIVE
  end

  test "failed viva grading shows a Grader error badge instead of Waiting to be graded" do
    save_viva_sub!(status: :grader_error, graded_at: nil, grader_comment: 'Grader error: boom')
    row = viva_row
    assert_select row, "a.badge[href=?]", viva_submission_path(@sub), text: /Grader error/
    refute_includes row.to_s, 'Waiting to be graded'
  end

  test "viva still in progress says so" do
    save_viva_sub!(status: :submitted, graded_at: nil, grader_comment: nil)
    row = viva_row
    assert_includes row.to_s, 'Interview in progress'
    refute_includes row.to_s, 'Waiting to be graded'
  end

  test "a code submission row shows the verdict strip and the evaluations link" do
    code = submissions(:add1_by_john)
    code.update_columns(status: Submission.statuses[:done], graded_at: 1.hour.ago, points: 50, grader_comment: 'P-P-')
    sign_in_as("john", "hello")
    get list_main_path
    assert_select ".verdict-strip[data-comment='P-P-'] .verdict-tile", count: 4
    assert_select ".verdict-legend-btn[data-bs-toggle=popover]", count: 1
    assert_select "a[href=?]", evaluations_submission_path(code)
  end
end
