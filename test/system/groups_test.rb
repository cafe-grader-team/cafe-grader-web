require "application_system_test_case"

class GroupsTest < ApplicationSystemTestCase
  test "create new group" do
    login("admin", "admin")
    visit groups_path

    click_on "New Group"
    # Name is a machine-readable identifier (NameFormatValidator: no spaces);
    # the human-readable text lives in Description.
    fill_in "Name", with: "Test_Group"
    click_on "Create Group"

    assert_text "Group was successfully created."
  end

  test "update group" do
    login("admin", "admin")
    visit edit_group_path(groups(:group_a))

    fill_in "Name", with: "Updated_Group"
    click_on "Save Changes"

    assert_text "Group was successfully updated."
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
