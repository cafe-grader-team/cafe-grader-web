require "test_helper"

# The device lock ("session lock", active while right.multiple_ip_login is
# false): the first browser a user is seen from after login is recorded in
# users.last_ip as that browser's `uuid` device cookie; any other browser is
# refused. Each open_session below is a separate browser with its own cookies.
class DeviceLockTest < ActionDispatch::IntegrationTest
  setup do
    set_grader_config('right.multiple_ip_login', false)
    users(:john).update_column(:last_ip, nil)
  end

  # a fresh browser: opens the site (gets its device cookie), then logs in
  def browser_logged_in_as_john
    s = open_session
    s.get root_path
    s.post login_login_path, params: { login: 'john', password: 'hello' }
    s
  end

  def john_login_cookies
    Login.where(user_id: users(:john).id).order(:id).pluck(:cookie)
  end

  test "the first browser takes the lock and keeps working" do
    a = browser_logged_in_as_john
    a.get list_main_path
    a.assert_response :success
    assert_equal john_login_cookies.last, users(:john).reload.last_ip
    a.get list_main_path
    a.assert_response :success
  end

  test "a refused browser is logged out but keeps its device cookie; the lock stays put" do
    a = browser_logged_in_as_john
    a.get list_main_path
    lock = users(:john).reload.last_ip

    b = browser_logged_in_as_john
    device_cookie_before = b.cookies['uuid']
    b.get list_main_path
    b.assert_redirected_to login_main_path
    assert_equal 'You cannot login from two different places', b.flash[:alert]
    assert_nil b.session[:user_id], 'refused browser must be logged out'
    assert_equal device_cookie_before, b.cookies['uuid'], 'device cookie must survive the logout'
    assert_equal lock, users(:john).reload.last_ip

    # now anonymous: the next heartbeat is an ordinary not-logged-in redirect ...
    b.post user_check_in_contests_path
    b.assert_redirected_to login_main_path
    assert_equal 'You need to log in', b.flash[:alert]

    # ... and it cannot retake the lock after an admin reset
    users(:john).update_column(:last_ip, nil)
    b.post user_check_in_contests_path
    b.assert_redirected_to login_main_path
    assert_nil users(:john).reload.last_ip

    a.get list_main_path
    a.assert_response :success, 'the holder is never affected'
  end

  test "after an admin reset the refused browser can log in again and take the lock; the old holder is then refused" do
    a = browser_logged_in_as_john
    a.get list_main_path
    b = browser_logged_in_as_john
    b.get list_main_path
    b.assert_redirected_to login_main_path

    users(:john).update_column(:last_ip, nil)   # admin: clear session lock
    b.post login_login_path, params: { login: 'john', password: 'hello' }
    b.get list_main_path
    b.assert_response :success

    cookies = john_login_cookies                # a, b, b again
    assert_equal 3, cookies.size
    assert_not_equal cookies[0], cookies[1]
    assert_equal cookies[1], cookies[2], 'same browser, same device id after the logout'
    assert_equal cookies[2], users(:john).reload.last_ip

    a.get list_main_path
    a.assert_redirected_to login_main_path
    assert_nil a.session[:user_id]
  end
end
