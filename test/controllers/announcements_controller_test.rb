require "test_helper"

class AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Fixture announcements `one`/`two` have no title and would fail
    # Announcement#title presence validation on update. Build a fresh one
    # for tests that mutate.
    @ann = Announcement.create!(title: "Hello", body: "World", published: false)
  end

  # --- Authorization ---

  test "unauthenticated cannot list announcements" do
    get announcements_path
    assert_redirected_to login_main_path
  end

  test "non-editor (no group) cannot list announcements" do
    sign_in_as("john", "hello")
    get announcements_path
    assert_redirected_to list_main_path
  end

  # --- Admin happy paths ---

  test "admin can access announcements index" do
    sign_in_as("admin", "admin")
    get announcements_path
    assert_response :success
  end

  test "admin can view new announcement form" do
    sign_in_as("admin", "admin")
    get new_announcement_path
    assert_response :success
  end

  test "admin can show an announcement" do
    sign_in_as("admin", "admin")
    get announcement_path(@ann)
    assert_response :success
  end

  test "admin can edit an announcement" do
    sign_in_as("admin", "admin")
    get edit_announcement_path(@ann)
    assert_response :success
  end

  test "admin can create announcement" do
    sign_in_as("admin", "admin")
    assert_difference("Announcement.count") do
      post announcements_path, params: {
        announcement: { title: "Test", body: "Hello", published: true, frontpage: false }
      }
    end
  end

  test "admin can update an announcement" do
    sign_in_as("admin", "admin")
    patch announcement_path(@ann), params: { announcement: { title: "Updated" } }
    assert_equal "Updated", @ann.reload.title
  end

  test "admin can destroy announcement" do
    sign_in_as("admin", "admin")
    announcement = Announcement.create!(title: "To delete", body: "test", published: false)
    assert_difference("Announcement.count", -1) do
      delete announcement_path(announcement)
    end
  end

  # --- Toggle endpoints ---

  test "admin can toggle published" do
    sign_in_as("admin", "admin")
    refute @ann.published?
    post toggle_published_announcement_path(@ann), as: :turbo_stream
    assert @ann.reload.published?
  end

  test "admin can toggle frontpage" do
    sign_in_as("admin", "admin")
    post toggle_front_announcement_path(@ann), as: :turbo_stream
    assert @ann.reload.frontpage?
  end
end
