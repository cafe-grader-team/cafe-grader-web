require 'test_helper'

# A student of a contest that turned outside login off, typing the outside
# password at either door: refused with a pointer to the seat slip, logged,
# but not counted toward the brute-force budget.
class OutsideLoginRefusalTest < ActionDispatch::IntegrationTest
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    contests(:contest_a).update!(outside_login_off: true)
  end

  teardown do
    Rails.cache = @original_cache
  end

  def failed_rows
    Login.where(success: false, attempted_login: 'james').count
  end

  def assert_uncounted
    assert_equal 0, Rails.cache.read(LoginThrottling.account_key('james')).to_i
    assert_equal 0, Rails.cache.read(LoginThrottling.ip_key('127.0.0.1')).to_i
  end

  test "web: blocked student with the right CU-net password is refused, told to use the slip, and not counted" do
    before = failed_rows
    with_outside_login do
      post login_login_path, params: { login: 'james', password: 'cunet-pass' }
      assert_redirected_to login_main_path
      assert_equal User.outside_login_refused_message, flash[:alert]
    end
    assert_nil session[:user_id]
    assert_equal before + 1, failed_rows
    assert_uncounted
  end

  test "web: blocked student with a wrong password is counted as today" do
    with_outside_login do
      post login_login_path, params: { login: 'james', password: 'nope' }
      assert_redirected_to login_main_path
      assert_equal 'Wrong password', flash[:alert]
    end
    assert_equal 1, Rails.cache.read(LoginThrottling.account_key('james')).to_i
  end

  test "web: blocked student with the slip password gets in" do
    with_outside_login do
      post login_login_path, params: { login: 'james', password: 'morning' }
      assert_redirected_to list_main_path
    end
  end

  test "api: refusal is a 401 with the message and is not counted" do
    before = failed_rows
    with_outside_login do
      post "/api/v1/auth/login", params: { login: 'james', password: 'cunet-pass' }, as: :json
      assert_response :unauthorized
      assert_equal User.outside_login_refused_message, response.parsed_body['error']
    end
    assert_uncounted
    assert_equal before + 1, failed_rows
  end
end
