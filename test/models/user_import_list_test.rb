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
end
