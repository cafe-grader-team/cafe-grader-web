require "test_helper"

# The model-layer submit lock (Submission#must_have_valid_problem) must block
# unauthorized model-layer saves (no controller involved) and permit
# authorized ones — matching User#can_submit_to_problem? exactly.
class SubmissionAuthorizationLockTest < ActiveSupport::TestCase
  def build(user, problem, source: "int main(){}")
    Submission.new(user: user, problem: problem, language: languages(:Language_cpp),
                   source: source, source_filename: "x.cpp", submitted_at: Time.zone.now)
  end

  setup do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
  end

  test "member saving to an in-group available problem: allowed" do
    assert build(users(:john), problems(:prob_add)).save
  end

  test "no-group user saving to a group problem: BLOCKED with authorization error" do
    sub = build(users(:jack), problems(:prob_add))
    assert_not sub.save
    assert_match(/Authorization error/, sub.errors.full_messages.join)
  end

  test "member saving to a draft problem: BLOCKED" do
    assert_not build(users(:john), problems(:prob_sub)).save
  end

  test "editor saving to a draft problem in their group: allowed (test-submit)" do
    assert build(users(:mary), problems(:prob_sub)).save
  end

  test "DISABLED-membership editor saving to a draft problem: BLOCKED" do
    GroupUser.where(user: users(:mary)).update_all(enabled: false)
    assert_not build(users(:mary), problems(:prob_sub)).save
  end

  test "binary submission (source nil) no longer skips the check: BLOCKED" do
    sub = Submission.new(user: users(:jack), problem: problems(:prob_add),
                         language: languages(:Language_cpp), binary: "PK\x03\x04",
                         source_filename: "x.zip", submitted_at: Time.zone.now)
    assert_not sub.save
    assert_match(/Authorization error/, sub.errors.full_messages.join)
  end

  test "admin saving to anything: allowed" do
    assert build(users(:admin), problems(:prob_sub)).save
  end

  test "updating an existing submission does not re-run authorization" do
    sub = build(users(:john), problems(:prob_add))
    assert sub.save
    # revoke the right, then update the row (as grading does)
    GroupUser.where(user: users(:john)).update_all(enabled: false)
    assert sub.update(points: 100, status: :done)
  end

  test "save!(validate: false) still bypasses (repair/replay/import contract)" do
    sub = build(users(:jack), problems(:prob_sub))
    assert_nothing_raised { sub.save!(validate: false) }
  end
end
