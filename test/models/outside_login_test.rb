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

  test "a ticked contest with no stop never blocks" do
    c = contests(:contest_a)
    c.update!(outside_login_off: true)
    c.update_column(:stop, nil)
    assert_not users(:james).outside_login_blocked?
  end

  test "ticking is audited" do
    assert_difference -> { AuditLog.where(auditable: contests(:contest_a)).count }, 1 do
      contests(:contest_a).update!(outside_login_off: true)
    end
    assert AuditLog.where(auditable: contests(:contest_a)).last.object_changes.key?('outside_login_off')
  end

  test "the slip password always works, even when blocked" do
    contests(:contest_a).update!(outside_login_off: true)
    with_outside_login { assert_equal users(:james), User.login_result('james', 'morning').user }
  end

  test "site switch off never asks the outside service" do
    without_outside_login do
      User.stub(:outside_password?, ->(*) { flunk 'must not call the outside service' }) do
        r = User.login_result('john', 'wrong')
        assert_nil r.user; assert_nil r.refusal
      end
    end
  end

  test "switch on, not blocked: outside password logs in and becomes the local one" do
    with_outside_login do
      assert_equal users(:john), User.login_result('john', 'cunet-pass').user
    end
    assert users(:john).reload.authenticated?('cunet-pass')
  end

  test "switch on, blocked, right outside password: refused and the slip password survives" do
    contests(:contest_a).update!(outside_login_off: true)
    with_outside_login do
      r = User.login_result('james', 'cunet-pass')
      assert_nil r.user
      assert_equal :slip_password_required, r.refusal
    end
    assert users(:james).reload.authenticated?('morning')
  end

  test "switch on, blocked, wrong outside password: plain failure" do
    contests(:contest_a).update!(outside_login_off: true)
    with_outside_login do
      r = User.login_result('james', 'nope')
      assert_nil r.user; assert_nil r.refusal
    end
  end

  test "unknown login and the authenticate wrapper" do
    assert_nil User.login_result('no_such_login', 'x').user
    assert_equal users(:john), User.authenticate('john', 'hello')
  end

  test "refusal message names the outside login" do
    with_outside_login do
      assert_equal "This exam uses the password on your seat slip. Your CU-net password will work again after the exam ends.",
                   User.outside_login_refused_message
    end
  end
end
