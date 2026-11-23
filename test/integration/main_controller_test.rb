require "test_helper"

class MainControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated user is redirected to login" do
    get list_main_path
    assert_redirected_to_login
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

  # Regression: a logged-in user whose session points at an enabled contest
  # they are NOT enrolled in has a nil contest-membership; the header countdown
  # read extra_time_second off it and 500'd every page (2 hits, 2026-09-09).
  test "list does not 500 when the session contest excludes the user" do
    set_grader_config("system.mode", "contest")
    contest = contests(:contest_a)
    membership = ContestUser.find_by(contest: contest, user: users(:james))  # james_in_contest_a
    sign_in_as("james", "morning")
    get set_active_contest_path(contest)                # sets session[:contest_id] while james is a member
    membership.destroy                                  # now the session points at a contest he is not in
    get list_main_path
    assert_response :success
  ensure
    set_grader_config("system.mode", "standard")
  end
end
