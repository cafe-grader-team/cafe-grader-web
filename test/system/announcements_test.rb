require "application_system_test_case"

class AnnouncementsTest < ApplicationSystemTestCase
  test "add new announcement" do
    visit root_path
    fill_in "Login", with: "admin"
    fill_in "Password", with: "admin"
    click_on "Login"
    assert_current_path list_main_path, wait: 5

    assert_text "MAIN"
    assert_text "Submission"

    within :css, 'header' do
      click_on "Manage"
      click_on "Announcements"
    end
    assert_text "Add Announcement"

    click_on "Add Announcement", match: :first

    fill_in 'Title', with: 'test'
    fill_in 'Body', with: 'test body 12345'
    check 'Published'

    click_on 'Create'

    visit list_main_path

    assert_text "test body 12345"

  end
  test "update announcement" do
    visit root_path
    fill_in "Login", with: "admin"
    fill_in "Password", with: "admin"
    click_on "Login"
    assert_current_path list_main_path, wait: 5

    visit edit_announcement_path(announcements(:one))

    fill_in "Title", with: "Updated Announcement Title"
    click_on "Save Changes"

    assert_text "Updated Announcement Title"
  end
end
