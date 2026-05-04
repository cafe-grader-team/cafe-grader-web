require "test_helper"

class UserAdminControllerTest < ActionDispatch::IntegrationTest
  # --- Index_query (Datatable JSON) ---

  test "admin can query user list as JSON" do
    sign_in_as("admin", "admin")
    post index_query_user_admin_index_path, as: :json
    assert_response :success
  end

  # --- Stat ---

  test "admin can view user stat" do
    sign_in_as("admin", "admin")
    get stat_user_admin_path(users(:john))
    assert_response :success
  end

  # --- Toggle enable/activate ---

  test "admin can toggle user enable" do
    sign_in_as("admin", "admin")
    u = users(:john)
    was = u.enabled
    get toggle_enable_user_admin_path(u), as: :js
    assert_equal !was, u.reload.enabled
  end

  test "admin can clear last_ip" do
    sign_in_as("admin", "admin")
    u = users(:john)
    u.update_column(:last_ip, "deadbeef")
    get clear_last_ip_user_admin_path(u)
    assert_nil u.reload.last_ip
  end

  # --- Forms ---

  test "admin can access import page" do
    sign_in_as("admin", "admin")
    get import_user_admin_index_path
    assert_response :success
  end

  test "do_import without a file redirects back to import" do
    sign_in_as("admin", "admin")
    post do_import_user_admin_index_path
    assert_redirected_to action: "import"
  end

  test "admin can access mass mailing form" do
    sign_in_as("admin", "admin")
    get mass_mailing_user_admin_index_path
    assert_response :success
  end

  test "admin can access bulk_manage form (GET)" do
    sign_in_as("admin", "admin")
    get bulk_manage_user_admin_index_path
    assert_response :success
  end

  test "admin can access active page" do
    sign_in_as("admin", "admin")
    get active_user_admin_index_path
    assert_response :success
  end

  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get user_admin_index_path
    assert_redirected_to login_main_path
  end

  test "normal user is redirected" do
    sign_in_as("john", "hello")
    get user_admin_index_path
    assert_redirected_to list_main_path
  end

  test "admin can access user admin index" do
    sign_in_as("admin", "admin")
    get user_admin_index_path
    assert_response :success
  end

  # --- CRUD ---

  test "admin can access new user form" do
    sign_in_as("admin", "admin")
    get new_user_admin_path
    assert_response :success
  end

  test "admin can create user" do
    sign_in_as("admin", "admin")
    assert_difference "User.count" do
      post user_admin_index_path, params: {
        user: {
          login: "newuser",
          full_name: "New User",
          password: "secret",
          password_confirmation: "secret"
        }
      }
    end
  end

  test "admin can edit user" do
    sign_in_as("admin", "admin")
    get edit_user_admin_path(users(:john))
    assert_response :success
  end

  test "admin can update user" do
    sign_in_as("admin", "admin")
    patch user_admin_path(users(:john)), params: {
      user: { full_name: "Updated John" }
    }
    assert_equal "Updated John", users(:john).reload.full_name
  end

  test "admin can destroy user" do
    sign_in_as("admin", "admin")
    user = users(:disabled_user)
    assert_difference "User.count", -1 do
      delete user_admin_path(user)
    end
  end

  test "admin can toggle activate" do
    sign_in_as("admin", "admin")
    user = users(:disabled_user)
    assert_not user.activated?
    get toggle_activate_user_admin_path(user)
    assert user.reload.activated?
  end

  test "create from list creates users" do
    sign_in_as("admin", "admin")
    post create_from_list_user_admin_index_path, params: {
      user_list: "bulkuser1,Bulk User One,pass1\nbulkuser2,Bulk User Two,pass2"
    }
    assert User.find_by_login("bulkuser1")
    assert User.find_by_login("bulkuser2")
  end

  # --- Admin / TA role panel ---

  test "non-admin cannot access admin role panel" do
    sign_in_as("john", "hello")
    get admin_user_admin_index_path
    assert_redirected_to list_main_path
  end

  test "admin can access admin role panel" do
    sign_in_as("admin", "admin")
    get admin_user_admin_index_path
    assert_response :success
    # both panels rendered with unique select ids
    assert_match 'id="admin_user_id"', response.body
    assert_match 'id="ta_user_id"', response.body
    # no duplicate id="id" left over from the old single-form layout
    assert_no_match(/<select[^>]*id="id"/, response.body)
  end

  test "admin_query returns admin role users as JSON" do
    sign_in_as("admin", "admin")
    post admin_query_user_admin_index_path
    assert_response :success
    logins = JSON.parse(response.body).fetch("data").map { |u| u["login"] }
    assert_includes logins, "admin"
  end

  test "ta_query returns ta role users as JSON" do
    sign_in_as("admin", "admin")
    users(:mary).roles << roles(:ta)
    post ta_query_user_admin_index_path
    assert_response :success
    logins = JSON.parse(response.body).fetch("data").map { |u| u["login"] }
    assert_includes logins, "mary"
    assert_not_includes logins, "admin"
  end

  test "ta_query returns empty data when ta role row is missing" do
    sign_in_as("admin", "admin")
    Role.find_by(name: "ta").destroy
    post ta_query_user_admin_index_path
    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch("data")
  end

  test "modify_role grants admin role" do
    sign_in_as("admin", "admin")
    user = users(:mary)
    assert_not user.roles.exists?(name: "admin")
    post modify_role_user_admin_index_path,
         params: { id: user.id, role: "admin", command: "grant" },
         as: :turbo_stream
    assert_response :success
    assert user.reload.roles.exists?(name: "admin")
  end

  test "modify_role grants ta role" do
    sign_in_as("admin", "admin")
    user = users(:mary)
    post modify_role_user_admin_index_path,
         params: { id: user.id, role: "ta", command: "grant" },
         as: :turbo_stream
    assert_response :success
    assert user.reload.roles.exists?(name: "ta")
  end

  test "modify_role revokes role" do
    sign_in_as("admin", "admin")
    user = users(:mary)
    user.roles << roles(:ta)
    post modify_role_user_admin_index_path,
         params: { id: user.id, role: "ta", command: "revoke" },
         as: :turbo_stream
    assert_response :success
    assert_not user.reload.roles.exists?(name: "ta")
  end

  test "modify_role refuses to revoke admin from root" do
    sign_in_as("admin", "admin")
    root = User.create!(login: "root", full_name: "Root", password: "rootroot",
                        password_confirmation: "rootroot", email: "root@root.com",
                        activated: true)
    root.roles << roles(:admin)
    post modify_role_user_admin_index_path,
         params: { id: root.id, role: "admin", command: "revoke" },
         as: :turbo_stream
    assert_response :success
    assert root.reload.roles.exists?(name: "admin"), "admin role should remain on root"
  end

  test "modify_role refuses self-revocation of admin" do
    sign_in_as("admin", "admin")
    me = users(:admin)
    post modify_role_user_admin_index_path,
         params: { id: me.id, role: "admin", command: "revoke" },
         as: :turbo_stream
    assert_response :success
    assert me.reload.roles.exists?(name: "admin"), "admin should not be able to revoke own admin role"
  end

  test "modify_role grant is idempotent" do
    sign_in_as("admin", "admin")
    user = users(:mary)
    user.roles << roles(:admin)
    before = user.roles.where(name: "admin").count
    post modify_role_user_admin_index_path,
         params: { id: user.id, role: "admin", command: "grant" },
         as: :turbo_stream
    assert_response :success
    assert_equal before, user.reload.roles.where(name: "admin").count
  end

  test "modify_role with unknown role does not change user roles" do
    sign_in_as("admin", "admin")
    user = users(:mary)
    before = user.roles.pluck(:name).sort
    post modify_role_user_admin_index_path,
         params: { id: user.id, role: "nonexistent", command: "grant" },
         as: :turbo_stream
    assert_response :success
    assert_equal before, user.reload.roles.pluck(:name).sort
  end
end
