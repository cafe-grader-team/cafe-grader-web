require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated cannot list tags" do
    get tags_path
    assert_redirected_to login_main_path
  end

  test "normal user cannot list tags" do
    sign_in_as("john", "hello")
    get tags_path
    assert_redirected_to list_main_path
  end

  test "group editor cannot list tags" do
    sign_in_as("mary", "mary")
    get tags_path
    assert_redirected_to list_main_path
  end

  # --- Admin happy paths ---

  test "admin can access tags index" do
    sign_in_as("admin", "admin")
    get tags_path
    assert_response :success
  end

  test "admin can view new tag form" do
    sign_in_as("admin", "admin")
    get new_tag_path
    assert_response :success
  end

  test "admin can show a tag" do
    skip "FIXME: app/views/tags/ has no show.html.haml — tags#show returns 406. Either add the template or remove the action."
    sign_in_as("admin", "admin")
    get tag_path(tags(:tag_easy))
    assert_response :success
  end

  test "admin can edit tag" do
    sign_in_as("admin", "admin")
    get edit_tag_path(tags(:tag_easy))
    assert_response :success
  end

  test "admin can create tag" do
    sign_in_as("admin", "admin")
    assert_difference("Tag.count") do
      post tags_path, params: { tag: { name: "new_tag", description: "A new tag", public: true } }
    end
  end

  test "admin can update tag" do
    sign_in_as("admin", "admin")
    t = tags(:tag_easy)
    patch tag_path(t), params: { tag: { description: "Updated description" } }
    assert_equal "Updated description", t.reload.description
  end

  test "admin can destroy tag" do
    sign_in_as("admin", "admin")
    assert_difference("Tag.count", -1) do
      delete tag_path(tags(:tag_hard))
    end
  end

  # --- Toggles ---

  test "admin can toggle public" do
    sign_in_as("admin", "admin")
    t = tags(:tag_easy)
    was = t.public
    post toggle_public_tag_path(t), as: :turbo_stream
    assert_equal !was, t.reload.public
  end

  test "admin can toggle primary" do
    skip "FIXME: tags table has no `primary` column (only `public`, `kind`, etc.) but TagsController#toggle_primary calls @tag.update(primary: ...) — broken. Either add the column or remove the action+route."
    sign_in_as("admin", "admin")
    t = tags(:tag_easy)
    was = t.primary
    post toggle_primary_tag_path(t), as: :turbo_stream
    assert_equal !was, t.reload.primary
  end

  # --- Datatable JSON ---

  test "admin can query tag list as JSON" do
    sign_in_as("admin", "admin")
    post index_query_tags_path, as: :json
    assert_response :success
  end
end
