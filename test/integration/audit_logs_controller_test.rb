require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # AuditLog has no fixture; create a row pointed at an existing fixture record.
    @audit = AuditLog.create!(
      auditable_type: "Contest",
      auditable_id:   contests(:contest_a).id,
      action:         "test_seed",
      user_id:        users(:admin).id
    )
  end

  # --- Authorization ---

  test "unauthenticated cannot list audit logs" do
    get audit_logs_path
    assert_redirected_to login_main_path
  end

  test "normal user cannot list audit logs" do
    sign_in_as("john", "hello")
    get audit_logs_path
    assert_redirected_to list_main_path
  end

  test "group editor cannot list audit logs" do
    sign_in_as("mary", "mary")
    get audit_logs_path
    assert_redirected_to list_main_path
  end

  # --- Read paths ---

  test "admin can list audit logs" do
    sign_in_as("admin", "admin")
    get audit_logs_path
    assert_response :success
  end

  test "admin can show a single audit log" do
    sign_in_as("admin", "admin")
    get audit_log_path(@audit)
    assert_response :success
  end

  # --- Filters (apply_scope branches) ---

  test "admin can filter by Contest auditable rollup" do
    sign_in_as("admin", "admin")
    get audit_logs_path, params: { auditable_type: "Contest", auditable_id: contests(:contest_a).id }
    assert_response :success
  end

  test "admin filter for missing Contest yields empty result page" do
    sign_in_as("admin", "admin")
    get audit_logs_path, params: { auditable_type: "Contest", auditable_id: 999_999 }
    assert_response :success
  end

  test "admin can filter by user_id" do
    sign_in_as("admin", "admin")
    get audit_logs_path, params: { user_id: users(:admin).id }
    assert_response :success
  end
end
