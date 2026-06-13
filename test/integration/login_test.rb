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
end
