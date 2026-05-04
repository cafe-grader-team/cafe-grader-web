require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get groups_path
    assert_redirected_to login_main_path
  end

  test "normal user is redirected from groups index" do
    sign_in_as("john", "hello")
    get groups_path
    assert_redirected_to list_main_path
  end

  test "admin can access groups index" do
    sign_in_as("admin", "admin")
    get groups_path
    assert_response :success
  end

  test "group editor can access groups index" do
    sign_in_as("mary", "mary")
    get groups_path
    assert_response :success
  end

  # --- Cross-group authorization ---
  #
  # Mary is editor of group_a only (role 2). She should be able to view/edit
  # group_a but not group_b.

  test "group editor can show their own editable group" do
    sign_in_as("mary", "mary")
    get group_path(groups(:group_a))
    assert_response :success
  end

  test "group editor cannot show a group they don't edit" do
    sign_in_as("mary", "mary")
    get group_path(groups(:group_b))
    assert_response :redirect
  end

  test "group editor cannot edit a group they don't own" do
    sign_in_as("mary", "mary")
    get edit_group_path(groups(:group_b))
    assert_response :redirect
  end

  # --- CRUD ---

  test "admin can create group" do
    sign_in_as("admin", "admin")
    assert_difference("Group.count") do
      post groups_path, params: { group: { name: "NewGroup", description: "Test" } }
    end
  end

  test "admin can view group" do
    sign_in_as("admin", "admin")
    get group_path(groups(:group_a))
    assert_response :success
  end

  test "admin can edit group" do
    sign_in_as("admin", "admin")
    get edit_group_path(groups(:group_a))
    assert_response :success
  end

  test "admin can update group" do
    sign_in_as("admin", "admin")
    g = groups(:group_a)
    patch group_path(g), params: { group: { description: "Updated" } }
    assert_equal "Updated", g.reload.description
  end

  test "admin can destroy group" do
    sign_in_as("admin", "admin")
    assert_difference("Group.count", -1) do
      delete group_path(groups(:group_b))
    end
  end

  # --- Toggle ---

  test "admin can toggle group enabled" do
    sign_in_as("admin", "admin")
    g = groups(:group_a)
    was = g.enabled
    post toggle_group_path(g), as: :turbo_stream
    assert_equal !was, g.reload.enabled
  end

  # --- do_all_users ---

  test "admin can disable all users in a group" do
    sign_in_as("admin", "admin")
    post do_all_users_group_path(groups(:group_a)), params: { command: "disable" }, as: :turbo_stream
    GroupUser.where(group: groups(:group_a)).each do |gu|
      assert_not gu.enabled
    end
  end

  # --- Datatable JSON queries ---

  test "admin can query users in group as JSON" do
    sign_in_as("admin", "admin")
    post show_users_query_group_path(groups(:group_a))
    assert_response :success
  end

  test "admin can query problems in group as JSON" do
    sign_in_as("admin", "admin")
    post show_problems_query_group_path(groups(:group_a)), as: :json
    assert_response :success
  end
end
