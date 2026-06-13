require "application_system_test_case"

class AnnouncementModalTest < ApplicationSystemTestCase
  setup do
    body = +"### Section One\n\nHello **students** of the course.\n\n"
    body << ('Filler sentence to push the preview past the clamp threshold. ' * 5)
    @ann = Announcement.create!(title: 'Course resources', author: 'staff',
                                body: body, published: true, frontpage: false, contest_only: false)
  end

  test "Read More opens the modal with the full rendered markdown" do
    login('john', 'hello')
    within "#announcement-#{@ann.id}" do
      # the card preview is rendered markdown (a real <h3>), clamped
      assert_selector '.announcement-preview-clamped h3', text: 'Section One'
      click_on 'Read More'
    end
    # Bootstrap adds .show once the modal is opened
    assert_selector "#announcementModal-#{@ann.id}.show", wait: 5
    within "#announcementModal-#{@ann.id}" do
      assert_selector 'h3', text: 'Section One'
      assert_selector 'strong', text: 'students'
    end
  end

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    # Login form uses Turbo, so Capybara may not auto-sync. Wait for the
    # post-login landing page to appear before returning.
    assert_current_path list_main_path, wait: 5
  end
end
