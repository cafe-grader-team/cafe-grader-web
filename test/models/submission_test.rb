require "test_helper"

class SubmissionTest < ActiveSupport::TestCase
  # --- Enums ---

  test "status enum values" do
    sub = submissions(:add1_by_admin)
    assert sub.respond_to?(:submitted?)
    assert sub.respond_to?(:evaluating?)
    assert sub.respond_to?(:done?)
    assert sub.respond_to?(:compilation_error?)
    assert sub.respond_to?(:grader_error?)
  end

  test "tag enum values" do
    sub = submissions(:add1_by_admin)
    assert sub.respond_to?(:tag_default?)
    assert sub.respond_to?(:tag_model?)
  end

  # --- Validations ---

  test "source length must not exceed 1 million" do
    sub = Submission.new(
      user: users(:admin),
      problem: problems(:prob_add),
      language: languages(:Language_c),
      source: "x" * 1_000_001
    )
    assert_not sub.valid?
    assert sub.errors[:source].any?
  end

  # --- Scopes ---

  test "by_id_range filters by id range" do
    all_ids = Submission.pluck(:id).sort
    min_id = all_ids.first
    max_id = all_ids.last
    filtered = Submission.by_id_range(min_id, max_id)
    assert_equal Submission.count, filtered.count
  end

  test "by_submitted_at filters by date range" do
    from = Time.zone.parse("2019-01-01")
    to = Time.zone.parse("2019-12-31")
    results = Submission.by_submitted_at(from, to)
    assert results.count > 0
  end

  # --- Methods ---

  test "set_grading_complete updates submission" do
    sub = submissions(:add1_by_admin)
    sub.set_grading_complete(85.0, "8/10", 150, 2048)
    sub.reload
    assert_equal 85.0, sub.points.to_f
    assert sub.done?
    assert_not_nil sub.graded_at
    assert_equal "8/10", sub.grader_comment
  end

  test "set_grading_error updates submission" do
    sub = submissions(:add1_by_admin)
    sub.set_grading_error("compile error")
    sub.reload
    assert_equal 0, sub.points.to_f
    assert sub.grader_error?
    assert_equal "compile error", sub.grader_comment
  end

  test "find_last_by_user_and_problem returns last submission" do
    admin = users(:admin)
    prob = problems(:prob_add)
    last = Submission.find_last_by_user_and_problem(admin.id, prob.id)
    assert_not_nil last
    assert_equal admin.id, last.user_id
    assert_equal prob.id, last.problem_id
  end

  test "find_last_by_user_and_problem returns nil when none exist" do
    result = Submission.find_last_by_user_and_problem(users(:mary).id, problems(:prob_add).id)
    assert_nil result
  end

  test "download_filename includes problem name and user login" do
    sub = submissions(:add1_by_admin)
    filename = sub.download_filename
    assert_includes filename, "add"
    assert_includes filename, "admin"
  end

  # --- Callbacks ---

  test "assign_latest_number assigns sequential numbers" do
    admin = users(:admin)
    prob = problems(:prob_add)
    existing_count = Submission.where(user: admin, problem: prob).count

    sub = Submission.new(
      user: admin,
      problem: prob,
      language: languages(:Language_c),
      source: "int main() { return 0; }",
      submitted_at: Time.zone.now
    )
    sub.save!
    assert_equal existing_count + 1, sub.number
  end

  # --- Associations ---

  test "submission belongs to user, problem, and language" do
    sub = submissions(:add1_by_admin)
    assert_equal users(:admin), sub.user
    assert_equal problems(:prob_add), sub.problem
    assert_equal languages(:Language_c), sub.language
  end

  test "submission has evaluations" do
    sub = submissions(:add1_by_admin)
    assert sub.evaluations.count > 0
  end
end
