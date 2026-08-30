require "application_system_test_case"

class TagsTest < ApplicationSystemTestCase
  test "create new tag" do
    login("admin", "admin")
    visit tags_path

    click_on "New Tag"
    fill_in "Name", with: "medium"
    click_on "Create Tag"

    assert_text "Tag was successfully created."
  end

  test "update tag" do
    login("admin", "admin")
    visit edit_tag_path(tags(:tag_easy))

    # clear via backspace first — a plain fill_in intermittently appends to the
    # pre-filled value (e.g. "easy" + "beginner" -> "easybeginner")
    fill_in "Name", with: "beginner", fill_options: { clear: :backspace }
    click_on "Save Changes"

    assert_text "Tag beginner was successfully updated."
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
