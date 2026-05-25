require "application_system_test_case"

# System-level guard for the owner-only viva answer form.
#
# Controller-side enforcement (VivaSessionsController#answer rejecting
# non-owner POSTs) is covered by test/integration/viva_sessions_controller_test.rb.
# This file covers the UI side: a non-owner (admin) viewing a viva
# session must not see the answer form at all — they see the "Viewing
# as observer" note instead.
class VivaSessionsTest < ApplicationSystemTestCase
  setup do
    @owner_sub = submissions(:add1_by_john) # owned by `john`
  end

  # ---- Helpers ----
  #
  # Building a viva submission needs more than what fixtures give us
  # (the production controller does a transactional create + initial
  # system turn). We do the same here so the page renders and the
  # sidebar references @submission.problem like in production.
  def make_viva_submission(user:, problem:)
    Submission.create!(
      user:     user,
      problem:  problem,
      language: languages(:Language_c), # nominal — viva problems ignore source
      source:   nil,
      source_filename: nil,
      status:   :submitted,
      submitted_at: Time.zone.now
    ).tap do |sub|
      sub.viva_turns.create!(role: :system, status: :ok, content: '(interview start)')
    end
  end

  # Active Storage attachment from raw bytes so the "Read" link in
  # _problem_name and the "Download problem statement" link in the
  # viva show sidebar both have a real attachment to point at.
  def attach_fake_pdf(problem)
    problem.statement.attach(
      io: StringIO.new("%PDF-1.4 fake test data"),
      filename: "#{problem.name}.pdf",
      content_type: "application/pdf"
    )
  end

  test "owner sees the answer form on their own viva session" do
    login "john", "hello"
    visit viva_submission_path(@owner_sub)
    assert_button "Send", wait: 5
    assert_no_text "Viewing as observer"
  end

  test "admin viewing someone else's viva sees observer note, not the form" do
    login "admin", "admin"
    visit viva_submission_path(@owner_sub)
    assert_text "Viewing as observer", wait: 5
    assert_no_button "Send"
  end

  test "Retry button appears on failed assistant turns for owner" do
    @owner_sub.viva_turns.create!(role: :assistant, status: :error, content: "boom")
    login "john", "hello"
    visit viva_submission_path(@owner_sub)
    assert_button "Retry", wait: 5
  end

  test "Retry button appears for admin viewing someone else's failed turn" do
    @owner_sub.viva_turns.create!(role: :assistant, status: :error, content: "boom")
    login "admin", "admin"
    visit viva_submission_path(@owner_sub)
    assert_button "Retry", wait: 5
  end

  test "Retry button absent on healthy (ok or processing) turns" do
    @owner_sub.viva_turns.create!(role: :assistant, status: :ok, content: "all good")
    login "john", "hello"
    visit viva_submission_path(@owner_sub)
    assert_no_button "Retry"
  end

  # --- PDF visibility on /main/list -------------------------------
  #
  # Confirms the controller-side gate (download_by_type) has a matching
  # UI hide on the busiest student-facing page. The helper test is in
  # the unit suite; this is the system-level smoke that the wiring
  # actually reaches the page.

  test "student does NOT see Read link on viva row at /main/list" do
    attach_fake_pdf(problems(:prob_add))
    attach_fake_pdf(problems(:prob_viva))
    login "john", "hello"
    visit list_main_path
    # Match by the actual hrefs the helper would emit. DataTables
    # rewrites the table on load so row-based selectors are fragile;
    # the URL is the stable contract.
    assert_no_link nil, href: download_by_type_problem_path(problems(:prob_viva), 'statement')
    assert_link    nil, href: download_by_type_problem_path(problems(:prob_add),  'statement')
  end

  # --- PDF visibility in /submissions/:id/viva sidebar -------------

  test "student does NOT see Download PDF link in viva session sidebar" do
    attach_fake_pdf(problems(:prob_viva))
    viva = make_viva_submission(user: users(:john), problem: problems(:prob_viva))
    login "john", "hello"
    visit viva_submission_path(viva)
    # Sidebar shows the problem name; PDF link sits next to it.
    assert_text "Viva Problem"
    assert_no_link nil, href: download_by_type_problem_path(problems(:prob_viva), 'statement')
  end

  test "admin DOES see Download PDF link in viva session sidebar" do
    attach_fake_pdf(problems(:prob_viva))
    viva = make_viva_submission(user: users(:john), problem: problems(:prob_viva))
    login "admin", "admin"
    visit viva_submission_path(viva)
    assert_link nil, href: download_by_type_problem_path(problems(:prob_viva), 'statement')
  end

  # --- Retry click end-to-end --------------------------------------
  #
  # Drives the full UI flow: owner clicks Retry on a stuck turn, the
  # controller resets it to :processing and re-enqueues the LLM job
  # (the test queue adapter swallows it). After the redirect the
  # "Interviewer is thinking..." spinner replaces the error message.

  # --- Form: viva-mode-toggle Stimulus controller ------------------
  #
  # When compilation_type is set to viva_exam, the form hides the
  # fields that don't apply (Allowed Language, Submission filename).
  # Verified end-to-end: load the edit page, click a radio, watch
  # the wrappers disappear / reappear.

  test "viva mode hides Allowed Language, Submission filename, View testcase, then restores" do
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_add)) # starts as self_contained
    # Visible to begin with.
    assert_selector "label", text: "Allowed Language"
    assert_selector "label", text: "Submission filename"
    assert_selector "label", text: "View testcase"

    choose "Viva Exam", allow_label_click: true
    # Stimulus has no async; the toggle is synchronous, but Capybara
    # waits up to default wait time for the assertion to be true.
    assert_no_selector "label", text: "Allowed Language"
    assert_no_selector "label", text: "Submission filename"
    assert_no_selector "label", text: "View testcase"
    # view_submission stays visible — admin may still want students
    # to see each other's viva transcripts (toggle remains useful).
    assert_selector "label", text: "View submission"

    choose "Self contained", allow_label_click: true
    assert_selector "label", text: "Allowed Language"
    assert_selector "label", text: "Submission filename"
    assert_selector "label", text: "View testcase"
  end

  test "viva problem edit page starts with non-applicable fields hidden" do
    # prob_viva is persisted as viva_exam → fields should be hidden
    # on first paint without any user click (connect() runs toggle()).
    login "admin", "admin"
    visit edit_problem_path(problems(:prob_viva))
    assert_no_selector "label", text: "Allowed Language"
    assert_no_selector "label", text: "Submission filename"
    assert_no_selector "label", text: "View testcase"
    assert_selector "label", text: "View submission"
  end

  test "owner clicks Retry and the turn flips back to :processing" do
    failed_turn = @owner_sub.viva_turns.create!(
      role: :assistant, status: :error, content: "boom"
    )
    login "john", "hello"
    visit viva_submission_path(@owner_sub)
    click_on "Retry"
    assert_text "Interviewer is thinking", wait: 5
    failed_turn.reload
    assert_predicate failed_turn, :processing?
    assert_nil failed_turn.content,
      "content should be cleared so the spinner has nothing to render"
  end

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    # Turbo-submitted login; sync before doing anything else (CLAUDE.md).
    assert_current_path list_main_path, wait: 5
  end
end
