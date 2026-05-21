require "test_helper"
require "minitest/mock" # for Object#stub used in can_view_problem_pdf? tests

class UserTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid user fixture" do
    assert users(:john).valid?
    assert users(:admin).valid?
  end

  test "login must be present" do
    user = User.new(full_name: "Test", password: "test1", password_confirmation: "test1")
    assert_not user.valid?
    assert user.errors[:login].any?
  end

  test "login must be unique" do
    user = User.new(login: "john", full_name: "Another John", password: "test1", password_confirmation: "test1")
    assert_not user.valid?
    assert user.errors[:login].any?
  end

  test "login must match format" do
    user = User.new(login: "bad login!", full_name: "Test", password: "test1", password_confirmation: "test1")
    assert_not user.valid?
    assert user.errors[:login].any?
  end

  test "login allows underscores and alphanumeric" do
    user = User.new(login: "good_Login123", full_name: "Test", password: "test1", password_confirmation: "test1")
    assert user.valid?
  end

  test "login must be at least 3 characters" do
    user = User.new(login: "ab", full_name: "Test", password: "test1", password_confirmation: "test1")
    assert_not user.valid?
  end

  test "full_name must be present" do
    user = User.new(login: "newuser", password: "test1", password_confirmation: "test1")
    assert_not user.valid?
    assert user.errors[:full_name].any?
  end

  test "password required for new user without hashed_password" do
    user = User.new(login: "newuser", full_name: "New User")
    assert_not user.valid?
    assert user.errors[:password].any?
  end

  test "password must be at least 4 characters" do
    user = User.new(login: "newuser", full_name: "New", password: "abc", password_confirmation: "abc")
    assert_not user.valid?
    assert user.errors[:password].any?
  end

  test "password confirmation must match" do
    user = User.new(login: "newuser", full_name: "New", password: "abcde", password_confirmation: "wrong")
    assert_not user.valid?
    assert user.errors[:password_confirmation].any?
  end

  # --- Authentication ---

  test "authenticate with valid credentials" do
    user = User.authenticate("john", "hello")
    assert_not_nil user
    assert_equal users(:john), user
  end

  test "authenticate with wrong password returns nil" do
    assert_nil User.authenticate("john", "wrong")
  end

  test "authenticate with non-existent user returns nil" do
    assert_nil User.authenticate("nonexistent", "hello")
  end

  test "authenticated? returns false for deactivated user" do
    user = users(:disabled_user)
    assert_not user.authenticated?("disabled")
  end

  test "authenticated? returns true for activated user with correct password" do
    assert users(:john).authenticated?("hello")
  end

  # --- Roles ---

  test "admin? returns true for admin user" do
    assert users(:admin).admin?
  end

  test "admin? returns false for normal user" do
    assert_not users(:john).admin?
  end

  test "has_role? checks specific role" do
    assert users(:admin).has_role?("admin")
    assert_not users(:john).has_role?("admin")
  end

  # --- Permissions ---

  test "admin can view any problem" do
    assert users(:admin).can_view_problem?(problems(:prob_add))
    assert users(:admin).can_view_problem?(problems(:prob_sub))
  end

  test "admin can edit any problem" do
    assert users(:admin).can_edit_problem?(problems(:prob_add))
  end

  test "admin can view any submission" do
    assert users(:admin).can_view_submission?(submissions(:add1_by_john))
  end

  test "user can view own submission when problem is available" do
    set_grader_config('system.use_problem_group', 'false')
    john = users(:john)
    sub = submissions(:add1_by_john)
    assert john.can_view_submission?(sub)
  end

  test "can_view_testcase requires config enabled" do
    set_grader_config('right.view_testcase', 'false')
    assert_not users(:john).can_view_testcase?(problems(:prob_add))

    set_grader_config('right.view_testcase', 'true')
    # john needs to be able to view the problem first
    set_grader_config('system.use_problem_group', 'false')
    assert users(:john).can_view_testcase?(problems(:prob_add))
  end

  # --- can_view_problem_pdf? ---
  #
  # The predicate has four branches that we exercise directly (stubbing
  # the underlying predicates) so test coverage doesn't depend on the
  # GraderConfiguration use_problem_group setting. The matrix:
  #
  #   role          | viva problem | non-viva problem
  #   admin         | allow        | allow
  #   editor        | allow        | allow
  #   reporter      | allow        | allow
  #   student       | DENY         | allow
  #   no view       | deny         | deny
  #
  # Integration coverage of the full controller flow lives in
  # problems_controller_test.rb.

  test "can_view_problem_pdf? admin allowed on viva problem" do
    assert users(:admin).can_view_problem_pdf?(problems(:prob_viva))
  end

  test "can_view_problem_pdf? admin allowed on non-viva problem" do
    assert users(:admin).can_view_problem_pdf?(problems(:prob_add))
  end

  test "can_view_problem_pdf? editor allowed on viva (mode irrelevant)" do
    john = users(:john)
    john.stub :can_edit_problem?, true do
      assert john.can_view_problem_pdf?(problems(:prob_viva))
    end
  end

  test "can_view_problem_pdf? reporter allowed on viva (mode irrelevant)" do
    john = users(:john)
    john.stub :can_edit_problem?, false do
      john.stub :can_report_problem?, true do
        assert john.can_view_problem_pdf?(problems(:prob_viva))
      end
    end
  end

  test "can_view_problem_pdf? student blocked on viva, allowed on non-viva" do
    set_grader_config('system.use_problem_group', 'false')
    john = users(:john)
    # john has neither edit nor report rights, but submit access via Problem.available.
    assert_not john.can_view_problem_pdf?(problems(:prob_viva))
    assert     john.can_view_problem_pdf?(problems(:prob_add))
  end

  test "can_view_problem_pdf? blocked when base can_view_problem? denies" do
    john = users(:john)
    john.stub :can_view_problem?, false do
      assert_not john.can_view_problem_pdf?(problems(:prob_viva))
      assert_not john.can_view_problem_pdf?(problems(:prob_add))
    end
  end

  # --- problems_for_action ---

  test "admin gets all problems for any action" do
    assert_equal Problem.count, users(:admin).problems_for_action(:submit).count
  end

  test "standard mode without group returns available problems for submit" do
    set_grader_config('system.mode', 'standard')
    set_grader_config('system.use_problem_group', 'false')
    john = users(:john)
    problems = john.problems_for_action(:submit)
    assert problems.all?(&:available?)
  end

  test "standard mode with group returns group-scoped problems" do
    set_grader_config('system.mode', 'standard')
    set_grader_config('system.use_problem_group', 'true')
    john = users(:john)
    problems = john.problems_for_action(:submit)
    # john is in group_a, which has prob_add (available) and prob_sub
    # group_submittable requires available: true
    assert_includes problems, problems(:prob_add)
  end

  # --- Scopes ---

  test "activated_users scope excludes deactivated users" do
    activated = User.activated_users
    assert_includes activated, users(:john)
    assert_not_includes activated, users(:disabled_user)
  end

  # --- Class methods ---

  test "random_password generates string of given length" do
    pw = User.random_password(8)
    assert_equal 8, pw.length
    assert_match(/\A[a-z]+\z/, pw)
  end

  test "random_password defaults to length 5" do
    pw = User.random_password
    assert_equal 5, pw.length
  end

  test "create_from_list creates users from CSV lines" do
    result = User.create_from_list("testuser1,Test User One,pass1\ntestuser2,Test User Two,pass2")
    assert_empty result[:error_logins]
    assert_equal 2, result[:created_users].count
    assert User.find_by_login("testuser1")
    assert User.find_by_login("testuser2")
  end

  test "create_from_list updates existing user" do
    result = User.create_from_list("john,Updated John,newpass")
    assert_equal 1, result[:updated_users].count
    assert_equal "Updated John", users(:john).reload.full_name
  end

  test "find_users_with_no_contest returns users without contests" do
    no_contest_users = User.find_users_with_no_contest
    assert_includes no_contest_users, users(:john)
    assert_not_includes no_contest_users, users(:james)
  end

  # --- Instance methods ---

  test "login_with_name returns formatted string" do
    assert_equal "[john] john", users(:john).login_with_name
  end

  test "contest_finished? returns false in standard mode" do
    set_grader_config('system.mode', 'standard')
    assert_not users(:john).contest_finished?
  end

  test "contest_started? returns true in standard mode" do
    set_grader_config('system.mode', 'standard')
    assert users(:john).contest_started?
  end

  test "active_contests returns none in standard mode" do
    set_grader_config('system.mode', 'standard')
    assert_empty users(:james).active_contests
  end

  test "active_contests returns enabled contests in contest mode" do
    set_grader_config('system.mode', 'contest')
    contests = users(:james).active_contests
    assert_includes contests, contests(:contest_a)
  end
end
