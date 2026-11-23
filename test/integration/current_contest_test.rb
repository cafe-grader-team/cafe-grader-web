require "test_helper"

# The session's current contest (ApplicationController#current_contest) — it
# drives the navbar countdown and where the check-in writes Last Seen. A
# session contest the student is no longer enrolled in must not be used
# (compas 2026-11-08: students removed from a contest kept it in their
# session, so their Last Seen in the real contest stayed blank).
class CurrentContestTest < ActionDispatch::IntegrationTest
  setup { set_grader_config('system.mode', 'contest') }
  teardown { reset_grader_config_cache }

  test "a session contest the student was removed from is dropped for their own" do
    sign_in_as("jack", "morning")                          # in contest_a and contest_b
    get set_active_contest_path(contests(:contest_b))
    contests_users(:jack_in_contest_b).destroy
    post user_check_in_contests_path
    assert_not_nil contests_users(:jack_in_contest_a).reload.last_heartbeat
  end

  test "a session contest whose membership was disabled is dropped too" do
    sign_in_as("jack", "morning")
    get set_active_contest_path(contests(:contest_b))
    contests_users(:jack_in_contest_b).update!(enabled: false)
    post user_check_in_contests_path
    assert_not_nil contests_users(:jack_in_contest_a).reload.last_heartbeat
    assert_nil contests_users(:jack_in_contest_b).reload.last_heartbeat
  end

  test "a running contest is chosen over an enabled one that has already ended" do
    contests(:contest_b).update_columns(start: 3.hours.ago, stop: 1.hour.ago)   # ends before contest_a
    sign_in_as("jack", "morning")
    post user_check_in_contests_path
    assert_not_nil contests_users(:jack_in_contest_a).reload.last_heartbeat
    assert_nil contests_users(:jack_in_contest_b).reload.last_heartbeat
  end
end
