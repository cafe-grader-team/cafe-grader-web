require 'test_helper'

class LoginTest < ActionDispatch::IntegrationTest
  test "login with invalid information" do
    get root_path
    assert_response :success
    post login_login_path, params: { login: "root", password: "hahaha" }
    assert_redirected_to login_main_path
  end

  test "normal user login" do
    get root_path
    assert_response :success
    post login_login_path, params: { login: "john", password: "hello" }
    assert_redirected_to list_main_path
  end

  test "normal user login in single_user mode" do
    set_grader_config('system.single_user_mode', 'true')
    get root_path
    assert_response :success
    post login_login_path, params: { login: "john", password: "hello" }
    follow_redirect!
    assert_redirected_to login_main_path
  end

  test "root login in single_user mode" do
    set_grader_config('system.single_user_mode', 'true')
    get root_path
    assert_response :success
    post login_login_path, params: { login: "admin", password: "admin" }
    assert_redirected_to list_main_path
  end

  test "logging in starts a fresh session: nothing from the browser's previous user carries over" do
    set_grader_config('system.mode', 'contest')
    post login_login_path, params: { login: "jack", password: "morning" }
    get list_main_path
    assert_not_nil session[:contest_id], "jack's session picks a contest"
    post login_login_path, params: { login: "james", password: "morning" }   # no logout in between
    assert_nil session[:contest_id]
    assert_equal users(:james).id, session[:user_id]
  ensure
    reset_grader_config_cache
  end

  # Bots probing for WordPress ask for "/" as JSON. The login page has only an
  # HTML view, so each probe was a 500 in the log (cp-grader, comprog, cedt:
  # a few a week). A browser, and curl's bare */*, still get the page.
  test "the front page answers a JSON request with 406, not a server error" do
    get root_path, params: { rest_route: "/wp/v2/users/me", context: "edit" },
                   headers: { "Accept" => "application/json" }
    assert_response :not_acceptable
    get root_path, headers: { "Accept" => "*/*" }
    assert_response :success
  end
end
