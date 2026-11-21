require "test_helper"

# A student's own contest window is contest.start minus their start offset to
# contest.stop plus their extra time, both in seconds. The problem list (and so
# submitting) and the submissions shown on the main list must use that window.
#
# These pin the 2026-11-21 bug: the problem scope added the offsets with MySQL
# ADDTIME(datetime, n), which reads n as a HHMMSS time — 600 added 6 minutes,
# 660 gave NULL and the student lost every problem the moment extra time was set.
class ContestUserWindowTest < ActiveSupport::TestCase
  setup do
    @contest = contests(:contest_a)
    @cu = contests_users(:james_in_contest_a)
    @james = users(:james)
  end

  def contest_problem_ids
    Problem.contests_problems_for_user(@james.id).pluck(:id)
  end

  test "extra time keeps the problems after the contest stops" do
    @contest.update_columns(start: 2.hours.ago, stop: 5.minutes.ago)
    assert_empty contest_problem_ids

    @cu.update!(extra_time_second: 660)   # ADDTIME read this as 00:06:60 → NULL
    assert_includes contest_problem_ids, problems(:prob_add).id
  end

  test "extra time is counted in seconds" do
    @contest.update_columns(start: 2.hours.ago, stop: 8.minutes.ago)
    @cu.update!(extra_time_second: 600)   # 10 minutes; ADDTIME gave 6
    assert_includes contest_problem_ids, problems(:prob_add).id

    @contest.update_columns(stop: 11.minutes.ago)
    assert_empty contest_problem_ids
  end

  test "a start offset opens the problems early, in seconds" do
    @contest.update_columns(start: 8.minutes.from_now, stop: 3.hours.from_now)
    assert_empty contest_problem_ids

    @cu.update!(start_offset_second: 600)
    assert_includes contest_problem_ids, problems(:prob_add).id
  end

  test "a legacy NULL extra time counts as none" do
    @cu.update_columns(extra_time_second: nil, start_offset_second: nil)
    assert_includes contest_problem_ids, problems(:prob_add).id
  end

  test "extra time must be whole, non-negative seconds" do
    @cu.extra_time_second = -60
    assert_not @cu.valid?
    @cu.extra_time_second = "1.5"
    assert_not @cu.valid?
    @cu.extra_time_second = 660
    assert @cu.valid?
  end

  test "active_contests_range covers the student's extra time and start offset" do
    set_grader_config('system.mode', 'contest')
    start = 2.hours.ago.change(usec: 0)
    stop = 5.minutes.ago.change(usec: 0)
    @contest.update_columns(start: start, stop: stop)
    @cu.update!(start_offset_second: 300, extra_time_second: 660)

    assert_includes @james.active_contests, @contest
    range = @james.active_contests_range
    assert_equal start - 300.seconds, range.begin
    assert_equal stop + 660.seconds, range.end
  end

  test "active_contests drops the contest once the student's extra time is over" do
    set_grader_config('system.mode', 'contest')
    @contest.update_columns(start: 2.hours.ago, stop: 15.minutes.ago)
    @cu.update!(extra_time_second: 660)
    assert_not_includes @james.active_contests, @contest
  end
end
