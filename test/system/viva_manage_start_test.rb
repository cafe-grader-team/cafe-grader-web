require "application_system_test_case"

# Cause-B regression (2026-08-23): an editor testing a STUDENT-HIDDEN viva
# (groups_problems.enabled=false) had no way to start it — the manage page's
# Submit button bounced viva problems to the main list, and the main list
# (student-scoped) never shows hidden problems. The manage page must offer
# Start Viva / View Viva directly for viva rows.
class VivaManageStartTest < ApplicationSystemTestCase
  setup do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")

    # start requires the seeded 'viva' Language (not in fixtures)
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }

    @viva = problems(:prob_viva)
    @viva.update!(viva_prompt: "# Rubric\nBe fair.")
    # student-hidden: in mary's group, in-group switch OFF — exactly the state
    # where the main list has no Start Viva button for anyone
    GroupProblem.create!(problem: @viva, group: groups(:group_a), enabled: false)
  end

  def login(username, password)
    visit root_path
    fill_in "login", with: username
    fill_in "password", with: password
    click_on "Login"
    # form_with submits via Turbo — sync before navigating (see CLAUDE.md)
    assert_current_path list_main_path, wait: 5
  end

  test "editor starts a student-hidden viva from the manage page" do
    login("mary", "mary")

    # the hidden viva is absent from the student-facing main list...
    assert_no_text @viva.full_name

    # ...but present on the manage page with a Start Viva button
    visit problems_path
    row = find("#prob-#{@viva.id}")
    assert row.has_no_link?("Submit"), "viva row must not offer the code-editor Submit"

    row.click_on "Start Viva"

    assert_current_path(%r{/submissions/\d+/viva}, wait: 10)
    sub = Submission.regular.where(user: users(:mary), problem: @viva, viva_archived_at: nil).first
    assert sub, "Start Viva must create an active viva submission for the editor"
  end

  test "viva row shows View Viva instead when the user already has an active session" do
    sub = Submission.create!(user: users(:mary), problem: @viva,
                             language: Language.find_by(name: "cpp"),
                             submitted_at: Time.zone.now, status: :submitted)

    login("mary", "mary")
    visit problems_path
    row = find("#prob-#{@viva.id}")

    assert row.has_no_button?("Start Viva"), "active session must replace Start Viva"
    row.click_on "View Viva"
    assert_current_path viva_submission_path(sub), wait: 10
  end

  test "non-viva rows keep the Submit button" do
    login("mary", "mary")
    visit problems_path
    within("#prob-#{problems(:prob_add).id}") do
      assert_link "Submit"
      assert_no_button "Start Viva"
    end
  end
end
