require "application_system_test_case"

# /problems/:id/stat in a real browser: the submissions table is filled by an
# AJAX request after the page paints, and the By-group card links to the report.
class ProblemStatTest < ApplicationSystemTestCase
  test "submissions table loads by AJAX and the By group card links to the report" do
    submissions(:add1_by_john).update_columns(points: 100, grader_comment: "PP")
    login("admin", "admin")
    visit stat_problem_path(problems(:prob_add))

    within("#main_table") do
      assert_selector "td", text: "john", wait: 10
      assert_selector "tbody tr", count: 3
    end
    within("#by-group-card") do
      assert_link "GroupA"
      assert_text "1 / 2"
    end
  end

  test "archived groups are folded and open on click" do
    old = Group.create!(name: "Cohort2568", enabled: false)
    GroupProblem.create!(group: old, problem: problems(:prob_add))
    GroupUser.create!(group: old, user: users(:jack), role: :user)
    login("admin", "admin")
    visit stat_problem_path(problems(:prob_add))

    within("#by-group-card") do
      assert_link "GroupA"
      assert_no_link "Cohort2568"                 # folded
      click_button "1 archived group"
      assert_link "Cohort2568", wait: 5           # unfolded
    end
  end

  private

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end
end
