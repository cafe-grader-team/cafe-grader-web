require 'test_helper'

# Brute-force throttling (LoginThrottling) across the web and API login
# doors. The test cache is a NullStore, so each test swaps in a real
# MemoryStore for the counters to accumulate.
class LoginThrottlingTest < ActionDispatch::IntegrationTest
  LIMIT = LoginThrottling::FAILURE_LIMIT

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
  end

  def fail_web(login: 'john', password: 'wrong', ip: nil)
    post login_login_path, params: { login: login, password: password },
         headers: ip ? { 'REMOTE_ADDR' => ip } : {}
    assert_redirected_to login_main_path
  end

  # Regression guard for the observed exam-start pattern: frustrated but
  # legitimate students retry ~20 times in 2-3 minutes. That burst must
  # never lock out the eventual correct login.
  test "frustrated exam-start burst below the limit does not block the correct login" do
    20.times { fail_web }
    post login_login_path, params: { login: 'john', password: 'hello' }
    assert_redirected_to list_main_path
  end

  test "failed attempts are recorded; throttled attempts never touch the database" do
    assert_difference -> { Login.where(success: false).count }, LIMIT do
      LIMIT.times { fail_web }
    end
    failure = Login.where(success: false).last
    assert_equal 'john', failure.attempted_login
    assert_equal users(:john).id, failure.user_id

    assert_no_difference -> { Login.count } do
      post login_login_path, params: { login: 'john', password: 'wrong' }
      assert_redirected_to login_main_path
      assert_match(/Too many failed login attempts/, flash[:alert])
    end
  end

  test "over the limit even the correct password is refused and no session opens" do
    LIMIT.times { fail_web }
    post login_login_path, params: { login: 'john', password: 'hello' }
    assert_redirected_to login_main_path
    assert_match(/Too many failed login attempts/, flash[:alert])
    assert_nil session[:user_id]
  end

  test "account budget pools across source IPs" do
    LIMIT.times { |i| fail_web(ip: "203.0.113.#{i + 1}") }
    post login_login_path, params: { login: 'john', password: 'hello' },
         headers: { 'REMOTE_ADDR' => '198.51.100.1' }
    assert_redirected_to login_main_path
    assert_match(/Too many failed login attempts/, flash[:alert])
  end

  test "ip budget pools across attempted accounts" do
    LIMIT.times { |i| fail_web(login: "nobody#{i}") }
    post login_login_path, params: { login: 'john', password: 'hello' }
    assert_redirected_to login_main_path
    assert_match(/Too many failed login attempts/, flash[:alert])

    post login_login_path, params: { login: 'john', password: 'hello' },
         headers: { 'REMOTE_ADDR' => '198.51.100.2' }
    assert_redirected_to list_main_path
  end

  test "successful login clears the account counter but not the ip counter" do
    (LIMIT - 1).times { fail_web }
    post login_login_path, params: { login: 'john', password: 'hello' }
    assert_redirected_to list_main_path

    # account counter was cleared by the success: a fresh round of failures
    # from other IPs stays under the account limit
    (LIMIT - 1).times { |i| fail_web(ip: "203.0.113.#{i + 1}") }
    post login_login_path, params: { login: 'john', password: 'hello' },
         headers: { 'REMOTE_ADDR' => '198.51.100.3' }
    assert_redirected_to list_main_path

    # the default IP's counter survived the success: one more failure trips it
    fail_web(login: 'mary')
    post login_login_path, params: { login: 'mary', password: 'mary' }
    assert_redirected_to login_main_path
    assert_match(/Too many failed login attempts/, flash[:alert])
  end

  # Exam gateways (right.login_throttle_exempt_ips): a room behind one NAT
  # address must not lock itself out (DS Quiz 2, 2026-10-07).
  test "an exempt address never trips the ip counter" do
    set_grader_config('right.login_throttle_exempt_ips', '10.0.5.40')
    (LIMIT + 5).times { |i| fail_web(login: "nobody#{i}", ip: '10.0.5.40') }
    post login_login_path, params: { login: 'john', password: 'hello' },
         headers: { 'REMOTE_ADDR' => '10.0.5.40' }
    assert_redirected_to list_main_path
  end

  test "an exempt CIDR range covers its addresses" do
    set_grader_config('right.login_throttle_exempt_ips', '192.0.2.0/24, 10.0.5.41')
    (LIMIT + 5).times { |i| fail_web(login: "nobody#{i}", ip: '192.0.2.77') }
    post login_login_path, params: { login: 'john', password: 'hello' },
         headers: { 'REMOTE_ADDR' => '192.0.2.77' }
    assert_redirected_to list_main_path
  end

  test "the account counter still applies at an exempt address" do
    set_grader_config('right.login_throttle_exempt_ips', '10.0.5.40')
    LIMIT.times { fail_web(ip: '10.0.5.40') }
    post login_login_path, params: { login: 'john', password: 'hello' },
         headers: { 'REMOTE_ADDR' => '10.0.5.40' }
    assert_redirected_to login_main_path
    assert_match(/Too many failed login attempts/, flash[:alert])
  end

  test "a malformed entry in the exempt list is skipped, not raised" do
    set_grader_config('right.login_throttle_exempt_ips', 'not-an-ip, 10.0.5.999 ,10.0.5.40')
    (LIMIT + 5).times { |i| fail_web(login: "nobody#{i}", ip: '10.0.5.40') }
    post login_login_path, params: { login: 'john', password: 'hello' },
         headers: { 'REMOTE_ADDR' => '10.0.5.40' }
    assert_redirected_to list_main_path

    # an address that is not listed is still counted
    LIMIT.times { |i| fail_web(login: "other#{i}") }
    post login_login_path, params: { login: 'mary', password: 'mary' }
    assert_redirected_to login_main_path
  end

  test "clear_recent! unlocks the address and the account and reports both" do
    LIMIT.times { fail_web(login: 'John') }
    locked = LoginThrottling.clear_recent!
    assert_equal({ '127.0.0.1' => LIMIT }, locked[:addresses])
    assert_equal({ 'john' => LIMIT }, locked[:accounts])

    post login_login_path, params: { login: 'john', password: 'hello' }
    assert_redirected_to list_main_path
  end

  test "clear_recent! reports nothing when no counter reached the limit" do
    3.times { fail_web }
    assert_equal({ addresses: {}, accounts: {} }, LoginThrottling.clear_recent!)
    assert_nil Rails.cache.read(LoginThrottling.ip_key('127.0.0.1'))
  end

  test "web and api draw down one shared failure budget" do
    (LIMIT / 2).times { fail_web }
    (LIMIT / 2).times do
      post "/api/v1/auth/login", params: { login: 'john', password: 'wrong' }, as: :json
      assert_response :unauthorized
    end
    assert_equal LIMIT, Login.where(success: false).count

    post "/api/v1/auth/login", params: { login: 'john', password: 'hello' }, as: :json
    assert_response :too_many_requests

    post login_login_path, params: { login: 'john', password: 'hello' }
    assert_redirected_to login_main_path
    assert_match(/Too many failed login attempts/, flash[:alert])
  end
end
