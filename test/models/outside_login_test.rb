require 'test_helper'

class OutsideLoginTest < ActiveSupport::TestCase
  test "master has no outside login" do
    skip 'this deployment has an outside login' if User.outside_login_available?   # chula_cp
    assert_nil User.outside_login_name
    assert_not User.outside_login_available?
    assert_not User.outside_login_on?
    assert_not User.outside_password?(users(:john), 'anything')
  end

  test "a student of a ticked contest is blocked; unticked is not" do
    assert_not users(:james).outside_login_blocked?
    contests(:contest_a).update!(outside_login_off: true)
    assert users(:james).outside_login_blocked?
  end

  test "an editor of a ticked contest is never blocked" do
    contests(:contest_a).update!(outside_login_off: true)
    assert_not users(:mary).outside_login_blocked?
  end

  test "the block ends at stop plus that student's extra time" do
    c = contests(:contest_a); c.update!(outside_login_off: true)
    contests_users(:james_in_contest_a).update!(extra_time_second: 600)
    assert users(:james).outside_login_blocked?(c.stop + 1.second)
    assert_not users(:james).outside_login_blocked?(c.stop + 601.seconds)
    assert_not users(:jack).outside_login_blocked?(c.stop + 1.second)
  end

  test "disabled contest and disabled row still block" do
    contests(:contest_a).update!(outside_login_off: true, enabled: false)
    contests_users(:james_in_contest_a).update!(enabled: false)
    assert users(:james).outside_login_blocked?
  end

  test "one ticked contest among several is enough" do
    contests(:contest_b).update!(outside_login_off: true)   # jack is in contest_a (unticked) and contest_b
    assert users(:jack).outside_login_blocked?
  end

  test "unticking mid-exam ends the block at once" do
    c = contests(:contest_a); c.update!(outside_login_off: true)
    c.update!(outside_login_off: false)
    assert_not users(:james).outside_login_blocked?
  end

  test "block end time is stop plus the longest student extra time" do
    c = contests(:contest_a)
    contests_users(:james_in_contest_a).update!(extra_time_second: 600)
    assert_equal c.stop + 600.seconds, c.outside_login_block_ends_at
    assert_nil Contest.new(name: 'nostop').outside_login_block_ends_at
  end

  test "ticking is audited" do
    assert_difference -> { AuditLog.where(auditable: contests(:contest_a)).count }, 1 do
      contests(:contest_a).update!(outside_login_off: true)
    end
    assert AuditLog.where(auditable: contests(:contest_a)).last.object_changes.key?('outside_login_off')
  end
end
