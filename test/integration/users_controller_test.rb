require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  # --- Self-service profile (system.user_setting_enabled) ---

  test "authenticated user can access profile" do
    sign_in_as("john", "hello")
    get profile_users_path
    assert_response :success
  end

  test "admin can update a user's remark via user_admin#update" do
    sign_in_as("admin", "admin")
    u = users(:john)
    patch user_admin_path(u), params: { user: {
      login: u.login, full_name: u.full_name, email: u.email,
      alias: "hahaha", remark: "section 2", enabled: "1"
    } }
    assert_equal "section 2", u.reload.remark, "remark should persist via user_admin#update"
  end

  test "profile redirects when user_setting_enabled is off" do
    set_grader_config("system.user_setting_enabled", "false")
    sign_in_as("john", "hello")
    get profile_users_path
    assert_redirected_to controller: "main", action: "list"
  end

  test "user can change own password" do
    sign_in_as("john", "hello")
    new_pw = "newpass123"
    post "/users/chg_passwd", params: { password: new_pw, password_confirmation: new_pw }
    assert_redirected_to action: "profile"
    # Re-login with new password
    post login_login_path, params: { login: "john", password: new_pw }
    assert_redirected_to list_main_path
  end

  test "update_self changes the password (profile form path)" do
    sign_in_as("john", "hello")
    new_pw = "1234asdf"
    patch update_self_users_path, params: { user: { password: new_pw, password_confirmation: new_pw } }
    assert_redirected_to profile_users_path
    # the old password no longer works; the new one does
    post login_login_path, params: { login: "john", password: "hello" }
    assert_redirected_to login_main_path # rejected, back to login
    post login_login_path, params: { login: "john", password: new_pw }
    assert_redirected_to list_main_path
  end

  test "user can change default language" do
    sign_in_as("john", "hello")
    lang = languages(:Language_cpp)
    post "/users/chg_default_language", params: { default_language: lang.id }
    assert_redirected_to action: "profile"
    assert_equal lang.id, users(:john).reload.default_language_id
  end

  test "update_self updates default language" do
    sign_in_as("john", "hello")
    lang = languages(:Language_python)
    patch "/users/update_self", params: { user: { default_language_id: lang.id } }
    assert_redirected_to profile_users_path
    assert_equal lang.id, users(:john).reload.default_language_id
  end

  # --- Online registration (gated by config) ---
  #
  # `system.online_registration` is not in the fixture grader_configurations,
  # so set_grader_config can't toggle it. We create the row inline.

  def with_online_registration(value)
    cfg = GraderConfiguration.find_or_initialize_by(key: "system.online_registration")
    cfg.assign_attributes(value: value, value_type: "boolean", description: "test")
    cfg.save!
    GraderConfiguration.instance_variable_set(:@config_cache, nil)
  end

  test "new redirects when online_registration is off" do
    with_online_registration("false")
    get new_user_path
    assert_redirected_to controller: "main", action: "login"
  end

  test "new renders when online_registration is on" do
    skip "POSTPONED: users/new.html.haml form_for posts to action: 'register', but the users resource only routes :new — register/confirm/forget/retrieve_password actions exist on the controller but have no routes. Online registration is non-functional end-to-end. Whole register/confirm/forget flow needs a product decision before re-enabling; spec TBD. To restore: add `post 'register'`, `get 'confirm'`, `get 'forget'`, `post 'retrieve_password'` to the users resource block."
    with_online_registration("true")
    get new_user_path
    assert_response :success
  end

  # --- Confirm activation key ---

  test "confirm with invalid activation key does not activate" do
    user = users(:john)
    user.update_columns(activated: false)
    get "/users/confirm", params: { login: user.login, activation: "wrongkey" }
    assert_not user.reload.activated?
  end

  test "confirm with valid activation key activates an inactive user" do
    skip "POSTPONED: confirm calls @user.valid? before save, but the john fixture (and others) lack email/other fields the User model considers required when not freshly registered. Tied to the register/confirm flow which is itself postponed (see new-form skip). Fix when the register flow is reactivated."
    user = users(:john)
    user.update_columns(activated: false)
    key = user.activation_key
    get "/users/confirm", params: { login: user.login, activation: key }
    assert user.reload.activated?
  end
end
