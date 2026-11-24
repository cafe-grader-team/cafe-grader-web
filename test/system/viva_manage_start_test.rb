require "application_system_test_case"

# Cause-B regression (2026-08-23): an editor testing a STUDENT-HIDDEN viva
# (groups_problems.enabled=false) had no way to start it — the manage page's
# Submit button bounced viva problems to the main list, and the main list
# (student-scoped) never shows hidden problems. Since 2026-09-23 the manage
# page offers **Test-drive** on viva rows: an editor's session on a hidden
# viva is a test session by definition, so it is flagged submissions.test_drive
# (excluded from reports and limits) rather than started as a real session.
class VivaManageStartTest < ApplicationSystemTestCase
  setup do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")

    # start requires the seeded 'viva' Language (not in fixtures)
    @viva_language = Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }

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

  test "editor test-drives a student-hidden viva from the manage page" do
    login("mary", "mary")

    # the hidden viva is absent from the student-facing main list...
    assert_no_text @viva.full_name

    # ...but present on the manage page with a Test-drive button
    visit problems_path
    row = find("#prob-#{@viva.id}")
    assert row.has_no_link?("Submit"), "viva row must not offer the code-editor Submit"
    assert row.has_no_button?("Start Viva"), "staff never start a real session from the manage page"

    row.click_on "Test-drive"

    assert_current_path(%r{/submissions/\d+/viva}, wait: 10)
    assert_selector "span.badge", text: "test-drive", wait: 5
    drive = Submission.test_drives.where(user: users(:mary), problem: @viva, viva_archived_at: nil).first
    assert drive, "Test-drive must create a flagged session for the editor"
    assert_empty Submission.regular.where(user: users(:mary), problem: @viva), "no real session may be created"
  end

  test "clicking Test-drive again reopens the editor's in-progress test-drive" do
    drive = Submission.create!(user: users(:mary), problem: @viva, language: @viva_language,
                               submitted_at: Time.zone.now, status: :submitted, test_drive: true)
    drive.viva_turns.create!(role: :assistant, status: :ok, content: "hello")

    login("mary", "mary")
    visit problems_path
    find("#prob-#{@viva.id}").click_on "Test-drive"

    assert_current_path viva_submission_path(drive), wait: 10
    assert_equal 1, Submission.test_drives.where(user: users(:mary), problem: @viva).count,
                 "a second click must reopen, not start another"
  end

  test "non-viva rows keep the Submit button" do
    login("mary", "mary")
    visit problems_path
    within("#prob-#{problems(:prob_add).id}") do
      assert_link "Submit"
      assert_no_button "Test-drive"
    end
  end
end
