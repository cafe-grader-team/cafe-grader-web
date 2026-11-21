require 'test_helper'

class UserImportListTest < ActiveSupport::TestCase
  test "password modes" do
    list = UserImportList.new("a,A\nb,B,\nc,C,pw")
    assert_equal [:random, :keep, :given], list.rows.map(&:password_mode)
    assert_equal 'pw', list.rows.last.password
    assert_nil list.rows.first.password
    assert_nil list.rows[1].password
  end

  test "line numbers and ignored lines" do
    list = UserImportList.new("a,A\nlonely\n\n  \nb,B")
    assert_equal [1, 5], list.rows.map(&:line_no)
    assert_equal [2], list.ignored_line_nos
  end

  test "CRLF line endings" do
    row = UserImportList.new("a,A,pw\r\n").rows.first
    assert_equal 'pw', row.password
    assert_equal 'A', row.full_name
  end

  test "remark is nil without a fifth field and blank with an empty one" do
    assert_nil UserImportList.new("a,A,pw,al").rows.first.remark
    assert_equal '', UserImportList.new("a,A,pw,al,").rows.first.remark
  end

  test "alias falls back to the login" do
    assert_equal 'al', UserImportList.new("a,A,pw,al").rows.first.user_alias
    assert_equal 'a', UserImportList.new("a,A,pw,").rows.first.user_alias
    assert_equal 'a', UserImportList.new("a,A").rows.first.user_alias
  end

  test "check sorts rows into categories" do
    users(:john).update!(remark: 'r0')
    c = without_outside_login { UserImportList.new("john,john,newpw,,r1\njames,James Renamed\njack,Jack,\nnewbie1,New Bie,pw\nlonely").check }
    assert_equal ['john'], c.new_password
    assert_equal ['james'], c.random_password
    assert_equal ['jack'], c.keep_password
    assert_equal ['newbie1'], c.new_accounts
    assert_equal ['james'], c.name_changes
    assert_equal ['john'], c.remark_changes
    assert_equal [5], c.ignored_line_nos
    assert_nil c.not_covered            # no outside login
    assert_equal 4, c.row_count
  end

  test "check matches logins case-insensitively and reports duplicates" do
    c = UserImportList.new("JOHN,john,pw\njohn,john,pw2").check
    assert_equal [], c.new_accounts
    assert_equal ['john'], c.duplicates
    assert_equal ['john'], c.new_password
  end

  test "blank lines and CRLF are not reported as ignored" do
    c = UserImportList.new("john,john,pw\r\n\r\n   \r\n").check
    assert_equal [], c.ignored_line_nos
    assert_equal ['john'], c.new_password
  end

  test "not covered lists new passwords outside a ticked contest" do
    contests(:contest_a).update!(outside_login_off: true)
    with_outside_login do
      c = UserImportList.new("james,james,pw\njohn,john,pw\nnewbie2,N,pw\njack,jack,").check
      assert_equal ['john', 'newbie2'], c.not_covered.sort   # james blocked; jack keeps his password
    end
  end

  test "check saves nothing" do
    assert_no_difference -> { User.count } do
      assert_no_difference -> { AuditLog.count } do
        UserImportList.new("newbie3,N,pw\njohn,Renamed,pw").check
      end
    end
    assert users(:john).reload.authenticated?('hello')
  end

  test "check and create agree on new accounts" do
    text = "john,john,pass\nnewbie4,N,pass\nNEWBIE5,M,\nnewbie4,N2,pass2"
    check = UserImportList.new(text).check
    created = User.create_from_list(text)[:created_users].pluck(:login)
    assert_equal check.new_accounts.map(&:downcase).sort, created.map(&:downcase).sort
  end

  test "duplicate rows combine the way Create applies them" do
    c = without_outside_login { UserImportList.new("john,John,newpw1\njohn,John,").check }
    assert_equal ['john'], c.new_password
    assert_equal [], c.keep_password
    assert_equal ['john'], c.duplicates
  end

  test "a given row then a random row combines to random; remark is the last non-nil; name is the last row's" do
    users(:john).update!(remark: 'r0')
    c = without_outside_login { UserImportList.new("john,Old,pw,,rem\njohn,John Final").check }
    assert_equal ['john'], c.random_password
    assert_equal [], c.new_password
    assert_equal ['john'], c.name_changes
    assert_equal ['john'], c.remark_changes
  end

  test "a combined password change makes a duplicate keep row count as not covered" do
    with_outside_login do
      c = UserImportList.new("john,John,newpw1\njohn,John,").check
      assert_equal ['john'], c.not_covered
    end
  end

  test "has_tabs is set when the text has a tab" do
    assert UserImportList.new("john\tJohn\tpw").check.has_tabs
    assert_not UserImportList.new("john,John,pw").check.has_tabs
  end
end
