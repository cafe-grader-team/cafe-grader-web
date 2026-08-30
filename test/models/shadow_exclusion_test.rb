# test/models/shadow_exclusion_test.rb
require 'test_helper'

class ShadowExclusionTest < ActiveSupport::TestCase
  setup do
    @original = submissions(:add1_by_john)
    @original.update_columns(status: Submission.statuses[:done], points: 40)
    @shadow = Submission.new(user: @original.user, problem: @original.problem,
                             language: @original.language, submitted_at: Time.zone.now,
                             source: "int main(){}", repaired_from_id: @original.id)
    @shadow.save!(validate: false)
    @shadow.update_columns(points: 100, status: Submission.statuses[:done])
  end

  test "students cannot view shadows, not even their own; admins can" do
    john = users(:john)
    assert john.can_view_submission?(@original)
    refute john.can_view_submission?(@shadow)
    assert users(:admin).can_view_submission?(@shadow)
  end

  test "last_submission_by_problem skips shadows" do
    assert_equal @original, users(:john).last_submission_by_problem(@original.problem)
  end

  test "find_last_by_user_and_problem skips shadows but number assignment does not" do
    assert_equal @original,
                 Submission.find_last_by_user_and_problem(@original.user_id, @original.problem_id)
    nxt = Submission.new(user: @original.user, problem: @original.problem,
                         language: @original.language, submitted_at: Time.zone.now,
                         source: "int main(){}")
    nxt.save!(validate: false)
    assert_equal @shadow.number + 1, nxt.number, "number sequence must count shadows"
  end

  test "problem stats exclude shadows" do
    # NOTE: prob_add already carries 3 regular submissions in fixtures
    # (add1_by_admin, add1_by_john, add1_by_james); @original is one of
    # them. The expected count below is that regular count, NOT 1 — the
    # point of the assertion is that adding @shadow does not bump it.
    regular_count = Submission.regular.where(problem_id: @original.problem_id).count
    stats = @original.problem.get_submission_stat
    assert_equal regular_count, stats[:total_sub]
    assert_equal 0, stats[:pass], "shadow's 100 points must not count as a pass"
  end

  test "problem_stat recompute excludes shadows" do
    regular_count = Submission.regular.where(problem_id: @original.problem_id).count
    ProblemStat.recompute_all
    ps = ProblemStat.find_by(problem_id: @original.problem_id)
    assert_equal regular_count, ps.sub_count
  end

  test "contest submissions exclude shadows" do
    contest = Contest.create!(name: 'nm-test', enabled: true,
                              start: 1.hour.ago, stop: 1.hour.from_now)
    contest.users << @original.user
    contest.problems << @original.problem
    @original.update_columns(submitted_at: Time.zone.now)
    @shadow.update_columns(submitted_at: Time.zone.now)
    assert_includes contest.submissions, @original
    refute_includes contest.submissions, @shadow
  end
end
