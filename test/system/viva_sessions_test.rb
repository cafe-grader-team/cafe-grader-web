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

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    # Turbo-submitted login; sync before doing anything else (CLAUDE.md).
    assert_current_path list_main_path, wait: 5
  end
end
