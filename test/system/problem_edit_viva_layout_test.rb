require "application_system_test_case"

# The viva edit layout end-to-end: the right-hand Viva Exam card saves through
# the one form, and switching compilation type swaps layouts live + on save.
class ProblemEditVivaLayoutTest < ApplicationSystemTestCase
  test "editing in the Viva Exam card saves through the one form" do
    login("admin", "admin")
    prob = problems(:prob_viva)
    visit edit_problem_path(prob)
    assert_selector "h5", text: "Viva Exam"
    fill_in "Soft turn cap", with: "9", fill_options: { clear: :backspace }
    within("[data-viva-exam-toggle-target=showForViva]") { click_on "Update Problem" }
    assert_selector ".toast", wait: 10   # turbo_stream response lands async
    assert_equal 9, prob.reload.viva_soft_cap
  end

  test "turning a regular problem into a viva swaps to the two-card layout, and back" do
    login("admin", "admin")
    prob = problems(:prob_add)
    visit edit_problem_path(prob)
    assert_selector "turbo-frame#dataset_select"

    choose "Viva Exam", allow_label_click: true
    assert_selector "label", text: "Soft turn cap"          # inline block revealed live
    click_on "Update Problem", match: :first
    assert_selector "h5", text: "Viva Exam", wait: 10       # whole body redrawn
    assert_no_selector "turbo-frame#dataset_select"
    assert prob.reload.viva_exam?

    choose "Self contained", allow_label_click: true
    assert_no_selector "h5", text: "Viva Exam"              # right card hidden live
    click_on "Update Problem", match: :first
    assert_selector "turbo-frame#dataset_select", wait: 10  # dataset layout is back
    assert_not prob.reload.viva_exam?
  end

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end
end
