require "application_system_test_case"

# Client-side status filter on the student main list (GitHub #29): segmented
# All | Unsolved | In progress | Solved buttons, a compact counter, and a
# Random button that flash-highlights an untried problem.
class MainListFilterTest < ApplicationSystemTestCase
  setup do
    submissions(:add1_by_john).update_columns(
      points: 100, graded_at: 1.hour.ago, grader_comment: "PPPP",
      status: Submission.statuses[:done])
    @solved_name  = name_re(problems(:prob_add).full_name)
    @untried_name = name_re(problems(:prob_viva).full_name)
  end

  # problem_name renders "_" as "_&ZeroWidthSpace;", and the zero-width space
  # survives into innerText — match names with it optional after each "_".
  def name_re(name) = /#{Regexp.escape(name).gsub("_", "_\u200B?")}/

  # scoped to the table — the submission box above it also lists problem names
  def assert_row(name)    = assert_selector("#main_table tbody tr", text: name)
  def assert_no_row(name) = assert_no_selector("#main_table tbody tr", text: name)

  test "status filter hides rows, counter follows, random flashes an untried row" do
    login("john", "hello")
    # the control is built by the DataTables layout hook on window load
    assert_selector "#problem-count", text: /problems/, wait: 10
    assert_row @solved_name

    click_on "Unsolved"
    assert_no_row @solved_name
    assert_row @untried_name
    assert_selector "#problem-count", text: /\d+ of \d+ problems/

    click_on "Solved"
    assert_row @solved_name
    assert_no_row @untried_name

    click_on "All"
    assert_row @solved_name
    click_on "Random"
    assert_selector "tr.row-flash", wait: 5
  end

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end
end
