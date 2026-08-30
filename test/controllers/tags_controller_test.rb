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

  test "admin can edit tag" do
    sign_in_as("admin", "admin")
    get edit_tag_path(tags(:tag_easy))
    assert_response :success
  end

  test "edit form hides public checkbox and shows staff-only notice for llm_kind tags" do
    sign_in_as("admin", "admin")
    llm_tag = Tag.create!(name: "codey-llm", kind: :llm_prompt, params: "helper prompt")
    get edit_tag_path(llm_tag)
    assert_response :success
    assert_match "Staff-only kind", response.body
    assert_select "input#tag_public", count: 0
  end

  test "edit form shows public checkbox and no staff-only notice for normal tags" do
    sign_in_as("admin", "admin")
    get edit_tag_path(tags(:tag_easy))
    assert_response :success
    assert_no_match "Staff-only kind", response.body
    assert_select "input#tag_public", count: 1
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

  # --- Datatable JSON ---

  test "admin can query tag list as JSON" do
    sign_in_as("admin", "admin")
    post index_query_tags_path, as: :json
    assert_response :success
  end
end
