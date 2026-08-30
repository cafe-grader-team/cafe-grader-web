require "application_system_test_case"

class ContestsTest < ApplicationSystemTestCase
  test "create new contest" do
    login("admin", "admin")
    visit contests_path

    click_on "New Contest"
    # Name is a machine-readable identifier (NameFormatValidator: no spaces);
    # the human-readable text lives in Description.
    fill_in "Name", with: "System_Test_Contest"
    click_on "Create Contest"

    assert_text "Contest was successfully created."
  end

  test "update contest" do
    login("admin", "admin")
    visit edit_contest_path(contests(:contest_a))

    fill_in "Name", with: "Updated_Contest"
    click_on "Save Changes"

    assert_text "Contest was successfully updated."
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
