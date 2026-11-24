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

  # The manage tables are DataTables fed by JSON; DataTables writes cell data
  # with innerHTML, so a name with markup used to render as markup (and its
  # onerror handler ran). A self-registered user controls their own full
  # name, so this was stored XSS aimed at whoever manages the contest.
  test "markup in a user's full name renders as text in the manage users table" do
    users(:james).update_columns(full_name: "James <b>Bond</b> <img src=x onerror=\"document.title='xss'\"> & co")
    login("admin", "admin")
    visit contest_path(contests(:contest_a))

    within("#tab-contest-user table") do
      assert_selector "td", text: "James <b>Bond</b> <img src=x onerror=\"document.title='xss'\"> & co", wait: 10
      assert_no_selector "b", text: "Bond"
      assert_no_selector "img"
    end
    assert_not_equal "xss", page.title
  end

  # The delete confirmation used to say only "Really delete this contest?",
  # so nothing on the popup showed which row's Destroy had been clicked.
  test "the contest delete confirmation names the contest" do
    login("admin", "admin")
    visit contests_path
    row = find("tr", text: "contest_b", wait: 10)
    within(row) { find("[data-bs-toggle=dropdown]").click }
    within(row) { click_on "Destroy" }
    assert_selector ".modal.show", text: 'Really delete contest "contest_b"?', wait: 5
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
