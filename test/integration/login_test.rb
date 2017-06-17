require 'test_helper'

class LoginTest < ActionDispatch::IntegrationTest
  # test "the truth" do
  #   assert true
  # end

  test "login with invalid information" do
    get root_path
    assert_response :success
    post login_login_path, login: "root", password: "hahaha"
    assert_redirected_to root_path
  end

  test "normal user login" do
    get root_path
    assert_response :success
    post login_login_path, {login: "john", password: "hello" }
    assert_redirected_to main_list_path
  end

  test "normal user login in single_user mode" do
    GraderConfiguration.find_by(key: GraderConfiguration::SINGLE_USER_KEY).update_attributes(value: 'true')
    GraderConfiguration.reload
    get root_path
    assert_response :success
    post login_login_path, {login: "john", password: "hello" }
    follow_redirect!
    assert_redirected_to root_path
  end

  test "root login in in single_user mode" do
    GraderConfiguration.find_by(key: GraderConfiguration::SINGLE_USER_KEY).update_attributes(value: 'true')
    GraderConfiguration.reload
    get root_path
    assert_response :success
    post login_login_path, {login: "admin", password: "admin" }
    assert_redirected_to main_list_path
  end
end
