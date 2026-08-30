require 'test_helper'

class SubmissionRepairTest < ActiveSupport::TestCase
  setup do
    @original = submissions(:add1_by_john)
    @original.update_columns(status: Submission.statuses[:done], points: 40)
  end

  def make_shadow(from: @original, points: nil)
    s = Submission.new(user: from.user, problem: from.problem, language: from.language,
                       submitted_at: Time.zone.now, source: "int main(){}",
                       repaired_from_id: from.id)
    s.save!(validate: false)
    s.update_columns(points: points, status: Submission.statuses[:done]) if points
    s
  end

  test "regular and shadow scopes partition submissions" do
    shadow = make_shadow
    assert_includes Submission.shadow, shadow
    refute_includes Submission.regular, shadow
    assert_includes Submission.regular, @original
    assert shadow.shadow?
    refute @original.shadow?
    assert_equal @original, shadow.repaired_from
  end

  test "shadow consumes the next number in the unique sequence" do
    shadow = make_shadow
    assert_equal @original.number + 1, shadow.number
  end

  test "attempt row links both directions" do
    shadow = make_shadow
    r = SubmissionRepair.create!(original_submission: @original, repaired_submission: shadow,
                                 status: :accepted, budget_lines: 2, budget_chars: 20)
    assert_equal @original, r.original_submission
    assert_includes @original.repair_attempts, r
  end

  test "fix_category rejects unknown values but allows nil" do
    r = SubmissionRepair.new(original_submission: @original, budget_lines: 2, budget_chars: 20)
    assert r.valid?
    r.fix_category = 'io_format'
    assert r.valid?
    r.fix_category = 'creative'
    refute r.valid?
  end

  test "batch_targets latest scope picks only the latest below-full submission" do
    user, problem = @original.user, @original.problem
    newer = Submission.new(user: user, problem: problem, language: @original.language,
                           submitted_at: Time.zone.now, source: "int main(){}")
    newer.save!(validate: false)
    newer.update_columns(points: 100, status: Submission.statuses[:done])
    # latest is full-score -> the (user, problem) pair yields no target
    ids = SubmissionRepair.batch_targets(problems: [problem], users: [user])
    assert_empty ids

    newer.update_columns(points: 30)
    ids = SubmissionRepair.batch_targets(problems: [problem], users: [user])
    assert_equal [newer.id], ids
  end

  test "batch_targets excludes shadows and respects score band" do
    shadow = make_shadow(points: 10)
    ids = SubmissionRepair.batch_targets(problems: [@original.problem], users: [@original.user], scope: 'all')
    refute_includes ids, shadow.id
    assert_includes ids, @original.id
    ids = SubmissionRepair.batch_targets(problems: [@original.problem], users: [@original.user],
                                         scope: 'all', min_score: 50)
    refute_includes ids, @original.id
  end
end
