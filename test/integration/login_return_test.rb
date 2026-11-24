require "test_helper"

# Issue #65: a logged-out visit to a page that needs a login comes back to that
# page after logging in (?next=). Only paths on this grader are followed, and
# only when logging in can help.
class LoginReturnTest < ActionDispatch::IntegrationTest
  setup do
    @sub = submissions(:add1_by_john)
    @page = submission_path(@sub)
  end

  teardown { reset_grader_config_cache }

  test "a logged-out page visit returns to that page after login" do
    get @page
    assert_redirected_to login_main_path(next: @page)
    follow_redirect!
    assert_select "form input[type=hidden][name=next][value=?]", @page
    post login_login_path, params: { login: "john", password: "hello", next: @page }
    assert_redirected_to @page
  end

  test "a wrong password keeps next for the second try" do
    post login_login_path, params: { login: "john", password: "nope", next: @page }
    assert_redirected_to login_main_path(next: @page)
    post login_login_path, params: { login: "john", password: "hello", next: @page }
    assert_redirected_to @page
  end

  test "next that leaves the grader, or points at login or logout, lands on the problem list" do
    ["https://evil.example/x", "//evil.example/x", "/\\evil.example", "javascript:alert(1)",
     "submissions/1", "/main/logout", "/main/login", "/login/login", "/"].each do |bad|
      post login_login_path, params: { login: "john", password: "hello", next: bad }
      assert_redirected_to list_main_path, "next=#{bad.inspect} must not be followed"
    end
    get list_main_path
    assert_response :success, "next=/main/logout must not have logged john out"
  end

  test "the login page does not carry an unsafe next" do
    get login_main_path(next: "https://evil.example/x")
    assert_select "input[name=next]", 0
  end

  test "next to a page the user may not see ends on the problem list with the usual message" do
    post login_login_path, params: { login: "john", password: "hello", next: contests_path }
    assert_redirected_to contests_path
    follow_redirect!
    assert_redirected_to list_main_path
  end

  test "a form posted while logged out returns to the page that held it" do
    contest = contests(:contest_a)
    post add_comment_contest_path(contest), params: { body: "x" },
         headers: { "Referer" => "http://www.example.com#{contest_path(contest)}?tab=1" }
    assert_redirected_to login_main_path(next: "#{contest_path(contest)}?tab=1")
  end

  test "a form posted from another site, or without a Referer, gets no next" do
    contest = contests(:contest_a)
    post add_comment_contest_path(contest), params: { body: "x" }, headers: { "Referer" => "https://evil.example/page" }
    assert_redirected_to login_main_path
    post add_comment_contest_path(contest), params: { body: "x" }
    assert_redirected_to login_main_path
  end

  test "background requests get no next; a turbo frame load returns to the page holding the frame" do
    post show_users_query_contest_path(contests(:contest_a)), as: :json
    assert_redirected_to login_main_path
    get @page, xhr: true
    assert_redirected_to login_main_path
    get @page, headers: { "Turbo-Frame" => "some_frame", "Referer" => "http://www.example.com/main/list" }
    assert_redirected_to login_main_path(next: "/main/list")
  end

  test "an expired session returns to the page after the new login" do
    sign_in_as("john", "hello")
    GraderConfiguration.find_or_create_by(key: GraderConfiguration::SYSTEM_MINIMUM_LAST_LOGIN_TIME)
                       .update!(value: 1.minute.from_now.to_s, value_type: 'string')
    reset_grader_config_cache
    get @page
    assert_redirected_to login_main_path(next: @page)
  end

  test "a refusal that logging in cannot fix gets no next" do
    sign_in_as("john", "hello")
    set_grader_config('system.single_user_mode', 'true')
    get @page
    assert_redirected_to login_main_path
  end
end
