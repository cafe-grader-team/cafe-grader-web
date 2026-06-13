require "test_helper"

class HeartbeatControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # Authorization tests
  # ============================================================

  test "unauthenticated user cannot hit heartbeat edit" do
    get "/heartbeat/anything/edit"
    assert_redirected_to login_main_path
  end

  test "authenticated user gets a heartbeat response" do
    sign_in_as("john", "hello")
    get "/heartbeat/anything/edit"
    assert_response :success
  end

end
