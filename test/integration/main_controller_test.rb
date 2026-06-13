require "test_helper"

class MainControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated user is redirected to login" do
    get list_main_path
    assert_redirected_to login_main_path
  end

  test "authenticated user can see list page" do
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success
  end

  test "login page loads successfully" do
    get root_path
    assert_response :success
  end

  test "logout redirects to root" do
    sign_in_as("john", "hello")
    get logout_main_path
    assert_response :redirect
  end

  test "admin can see list page" do
    sign_in_as("admin", "admin")
    get list_main_path
    assert_response :success
  end

  test "submit creates submission via editor" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    lang = languages(:Language_c)
    assert_difference "Submission.count" do
      post submit_main_path, params: {
        submission: { problem_id: prob.id },
        language_id: lang.id,
        editor_text: "int main() { return 0; }"
      }
    end
  end

  test "help page loads" do
    sign_in_as("john", "hello")
    get help_main_path
    assert_response :success
  end

  # --- Dead actions (no routes) ---
  #
  # MainController defines `source`, `load_output`, `confirm_contest_start`,
  # and `error` actions, but none are routed in config/routes.rb. The
  # singular `resource :main` block only routes login/logout/list/help/submit
  # /submission/prob_grop. These actions are therefore unreachable; either
  # add routes or remove the actions.

  test "main#source is not routed (DEAD action)" do
    assert_raises(ActionController::UrlGenerationError) do
      url_for(controller: "main", action: "source", only_path: true)
    end
  end

  test "main#load_output is not routed (DEAD action)" do
    assert_raises(ActionController::UrlGenerationError) do
      url_for(controller: "main", action: "load_output", only_path: true)
    end
  end

  test "main#confirm_contest_start is not routed (DEAD action)" do
    assert_raises(ActionController::UrlGenerationError) do
      url_for(controller: "main", action: "confirm_contest_start", only_path: true)
    end
  end
end
