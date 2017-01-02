require 'test_helper'

class LoginTest < ActionDispatch::IntegrationTest
  # test "the truth" do
  #   assert true
  # end

  test "login with valid information" do
    get root_path
    assert_response :success

  end
end
