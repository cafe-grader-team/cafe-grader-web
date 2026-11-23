require "test_helper"

class ConfigurationsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get grader_configuration_index_path
    assert_redirected_to_login
  end

  test "normal user is redirected" do
    sign_in_as("john", "hello")
    get grader_configuration_index_path
    assert_redirected_to list_main_path
  end

  test "group editor is redirected" do
    sign_in_as("mary", "mary")
    get grader_configuration_index_path
    assert_redirected_to list_main_path
  end

  # --- Index/edit/update/toggle ---

  # --- Clear Login Locks ---

  test "admin clears login locks and the toast names what was locked" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    sign_in_as("admin", "admin")
    # a room behind 10.0.5.40 has used up its failure budget
    Login.create!(attempted_login: 'nobody', ip_address: '10.0.5.40', success: false)
    LoginThrottling::FAILURE_LIMIT.times do
      Rails.cache.increment(LoginThrottling.ip_key('10.0.5.40'), 1, expires_in: LoginThrottling::WINDOW)
    end

    post clear_login_locks_grader_configuration_index_path, as: :turbo_stream
    assert_response :success
    assert_match(/Unlocked address 10.0.5.40 \(#{LoginThrottling::FAILURE_LIMIT} failures\)/, response.body)
    assert_nil Rails.cache.read(LoginThrottling.ip_key('10.0.5.40'))
  ensure
    Rails.cache = original_cache
  end

  test "group editor cannot clear login locks" do
    sign_in_as("mary", "mary")
    post clear_login_locks_grader_configuration_index_path
    assert_redirected_to list_main_path
  end

  test "admin can access index" do
    sign_in_as("admin", "admin")
    get grader_configuration_index_path
    assert_response :success
  end

  test "a setting's Change history link leaves its turbo frame" do
    # Inside a turbo frame Turbo takes a left-click even with Drive off and
    # loads the audit log into the frame ("Content missing").
    sign_in_as("admin", "admin")
    get grader_configuration_index_path
    assert_select "turbo-frame a[href*='audit_logs'][data-turbo='false']", minimum: 1
    assert_select "turbo-frame a[href*='audit_logs']:not([data-turbo='false'])", 0
  end

  test "admin can update configuration" do
    sign_in_as("admin", "admin")
    config = GraderConfiguration.find_by(key: "ui.front.title")
    patch grader_configuration_path(config), params: {
      grader_configuration: { value: "New Title" }
    }
    assert_equal "New Title", config.reload.value
  end

  # The login check skips a bad exempt-list entry silently, so the page is
  # where the mistake has to show: under the setting, and right after a save.
  test "saving an exempt list with a bad entry shows a warning under the setting" do
    sign_in_as("admin", "admin")
    config = GraderConfiguration.find_by(key: GraderConfiguration::LOGIN_THROTTLE_EXEMPT_IPS_KEY)
    patch grader_configuration_path(config), params: {
      grader_configuration: { value: "10.0.5.40;10.0.5.41" }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", "config_warnings_grader_configuration_#{config.id}" do
      assert_select "template", text: /'10.0.5.40;10.0.5.41' is not an address or range/
    end

    get grader_configuration_index_path
    assert_select "#config_warnings_grader_configuration_#{config.id}:not([hidden])", text: /is not an address or range/
  end

  test "a well-formed exempt list leaves the warning area empty and hidden" do
    sign_in_as("admin", "admin")
    config = GraderConfiguration.find_by(key: GraderConfiguration::LOGIN_THROTTLE_EXEMPT_IPS_KEY)
    patch grader_configuration_path(config), params: {
      grader_configuration: { value: "10.0.5.40, 10.0.5.41" }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_no_match(/not an address or range|covers every address/, response.body)

    get grader_configuration_index_path
    assert_select "#config_warnings_grader_configuration_#{config.id}[hidden]"
    assert_select ".config-warnings .alert", count: 0
  end

  test "admin can toggle boolean configuration" do
    sign_in_as("admin", "admin")
    config = GraderConfiguration.find_by(key: "system.single_user_mode")
    patch toggle_grader_configuration_path(config)
    assert_equal "true", config.reload.value
  end

  test "admin can edit configuration" do
    sign_in_as("admin", "admin")
    config = GraderConfiguration.find_by(key: "ui.front.title")
    get edit_grader_configuration_path(config)
    assert_response :success
  end

  # --- Collection actions ---

  test "admin can reload config cache" do
    sign_in_as("admin", "admin")
    get reload_grader_configuration_index_path
    assert_response :redirect
  end

  test "admin can clear all user IPs" do
    sign_in_as("admin", "admin")
    # Set a user's last_ip so we can verify the clear effect
    users(:john).update_column(:last_ip, "deadbeef")
    post clear_user_ip_grader_configuration_index_path, as: :turbo_stream
    assert_response :success
    assert_nil users(:john).reload.last_ip
  end

  test "admin can set exam right which cascades to system mode" do
    sign_in_as("admin", "admin")
    get set_exam_right_grader_configuration_index_path(value: "true")
    assert_response :redirect # redirects to index
  end
end
