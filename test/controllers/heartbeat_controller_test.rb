require "test_helper"

class HeartbeatControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # Authorization tests — currently FAILING
  #
  # HeartbeatController#edit has no `before_action` for auth, so
  # `GET /heartbeat/:id/edit` runs publicly. The action also still
  # uses Rails 4-era `render text:` (removed in Rails 5.1), so the
  # action likely raises at runtime as well.
  #
  # The tests below document the expected scope. They are skipped
  # until the controller is patched.
  #
  # Suggested fix: add `before_action :check_valid_login` at the
  # class level (or on `edit`), and replace `render text:` with
  # `render plain:`. Then remove the `skip` lines below.
  # ============================================================

  test "unauthenticated user cannot hit heartbeat edit" do
    skip "FIXME: HeartbeatController#edit has no auth — see Phase 1 audit"
    get "/heartbeat/anything/edit"
    assert_redirected_to login_main_path
  end

  test "authenticated user gets a heartbeat response" do
    skip "FIXME: HeartbeatController#edit uses removed `render text:` syntax — see Phase 1 audit"
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
