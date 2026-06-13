require "application_system_test_case"

# Reactive disclosure on the dataset card of /problems/:id/edit,
# driven by the dataset-mode-toggle Stimulus controller:
#
#   * Manager section + main_filename — hidden when problem's
#     compilation_type is :self_contained (compiler.rb:87 never
#     reaches those code paths in that mode).
#   * Checker section — hidden when dataset's evaluation_type is
#     NOT in {custom_cafe, custom_cms, custom_cms_raw}.
#
# These wrappers carry data-dataset-mode-toggle-target attributes;
# the controller toggles d-none on them. We assert via class-presence
# (visible: :all) so the tab-pane visibility from the tab system
# doesn't confound the test.
class ProblemEditDatasetFormTest < ApplicationSystemTestCase
  test "self_contained problem hides Manager section and main_filename" do
    # prob_add defaults to compilation_type :self_contained.
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_add))
    # Both hideForSelfContained targets must have d-none on initial paint.
    assert_selector "[data-dataset-mode-toggle-target='hideForSelfContained'].d-none",
                    count: 2, visible: :all, wait: 5
  end

  test "with_managers problem shows Manager section and main_filename" do
    problems(:prob_add).update!(compilation_type: :with_managers)
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_add))
    # No d-none on either hideForSelfContained target.
    assert_no_selector "[data-dataset-mode-toggle-target='hideForSelfContained'].d-none",
                       visible: :all, wait: 5
    # And the targets themselves still exist (just not hidden).
    assert_selector "[data-dataset-mode-toggle-target='hideForSelfContained']",
                    count: 2, visible: :all
  end

  test "switching compilation_type from self_contained to with_managers reveals Manager section" do
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_add))
    # Sanity: initially hidden.
    assert_selector "[data-dataset-mode-toggle-target='hideForSelfContained'].d-none",
                    count: 2, visible: :all, wait: 5
    # Flip the radio in the LEFT-COLUMN problem form. The
    # viva-mode-toggle controller dispatches a window event;
    # dataset-mode-toggle picks it up and refreshes.
    choose "With managers", allow_label_click: true
    assert_no_selector "[data-dataset-mode-toggle-target='hideForSelfContained'].d-none",
                       visible: :all, wait: 5
  end

  test "default evaluation_type hides the Checker section" do
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_add))
    # ds_add has evaluation_type :default → Checker hidden.
    assert_selector "[data-dataset-mode-toggle-target='hideUnlessCustomEval'].d-none",
                    visible: :all, wait: 5
  end

  test "switching evaluation_type to custom_cms reveals the Checker section" do
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_add))
    assert_selector "[data-dataset-mode-toggle-target='hideUnlessCustomEval'].d-none",
                    visible: :all, wait: 5
    # The evaluation_type select lives in the Settings tab (default
    # active), so it's reachable without switching tabs. Labels were
    # reworded to "[BRACKET] description" form; pick the CMS option.
    select "[CMS] CMS/Codeforces protocol (score on stdout)", from: "dataset_evaluation_type"
    assert_no_selector "[data-dataset-mode-toggle-target='hideUnlessCustomEval'].d-none",
                       visible: :all, wait: 5
  end

  test "saved custom_cms dataset shows Checker section on initial paint" do
    problems(:prob_add).live_dataset.update!(evaluation_type: :custom_cms)
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_add))
    # Initial connect() should read the (now non-empty) value and
    # leave the section unhidden.
    assert_no_selector "[data-dataset-mode-toggle-target='hideUnlessCustomEval'].d-none",
                       visible: :all, wait: 5
  end

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end
end
