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

  # ============================================================
  # Routing concern — currently DEAD
  #
  # HeartbeatController defines `index` and protects it via
  # `before_action :admin_authorization`, but routes.rb only routes
  # `get 'heartbeat/:id/edit'`. There is no route to `index`, so the
  # action is dead code. Either:
  #   - Add `resources :heartbeat, only: [:index]` (or similar) to
  #     routes.rb and write a real test here, or
  #   - Delete the `index` action.
  # ============================================================

  test "heartbeat index route is missing (DEAD action)" do
    assert_raises(ActionController::UrlGenerationError) do
      get url_for(controller: "heartbeat", action: "index", only_path: true)
    end
  end
end
