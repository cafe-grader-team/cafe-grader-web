require "test_helper"

class SubmissionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
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

  # --- fail_stale_viva_evaluating! (see Submission::STALE_EVALUATING_AFTER) ---

  # `viva` Language isn't in fixtures — find_or_create_by! so this works
  # whether or not another test already seeded it within this run.
  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  def make_viva_submission(status:, user: users(:john))
    Submission.create!(user: user, problem: problems(:prob_viva), language: viva_language,
                        status: status, submitted_at: Time.zone.now)
  end

  # Helper: bypass the touch-on-save so we can backdate updated_at directly
  # (mirrors VivaTurnTest#stamp_updated_at).
  def stamp_updated_at(record, time)
    record.class.where(id: record.id).update_all(updated_at: time)
    record.reload
  end

  test "fail_stale_viva_evaluating! marks a stale evaluating viva submission as grader_error" do
    sub = make_viva_submission(status: :evaluating)
    stamp_updated_at(sub, 21.minutes.ago)

    count = Submission.fail_stale_viva_evaluating!
    sub.reload

    assert_equal 1, count
    assert_predicate sub, :grader_error?
    assert_match(/timed out/i, sub.grader_comment)
  end

  test "fail_stale_viva_evaluating! leaves fresh evaluating viva submissions alone" do
    sub = make_viva_submission(status: :evaluating)
    # updated_at defaults to now — within the threshold.

    count = Submission.fail_stale_viva_evaluating!
    sub.reload

    assert_equal 0, count
    assert_predicate sub, :evaluating?
  end

  test "fail_stale_viva_evaluating! leaves a stale evaluating submission alone if a viva_grade row already exists" do
    sub = make_viva_submission(status: :evaluating)
    VivaGrade.create!(submission: sub)
    stamp_updated_at(sub, 21.minutes.ago)

    count = Submission.fail_stale_viva_evaluating!
    sub.reload

    assert_equal 0, count, "a viva_grade row already existing means grading is mid-write — a different bug, not this sweeper's job"
    assert_predicate sub, :evaluating?
  end

  # --- reap_abandoned_vivas! (see Submission::ABANDONED_VIVA_REAP_AFTER) ---

  def make_abandoned_viva(with_student_turn:, idle: 25.hours)
    sub = make_viva_submission(status: :submitted)
    sub.update_column(:submitted_at, Time.zone.now - idle)
    greeting = sub.viva_turns.create!(role: :assistant, status: :ok, content: 'hello')
    stamp_updated_at(greeting, Time.zone.now - idle)
    if with_student_turn
      t = sub.viva_turns.create!(role: :student, status: :ok, content: 'my answer')
      stamp_updated_at(t, Time.zone.now - idle)
    end
    sub
  end

  test "reap_abandoned_vivas! grades an idle session that has a student answer" do
    sub = make_abandoned_viva(with_student_turn: true)
    assert_enqueued_with(job: Llm::VivaGradeAssistJob) do
      assert_equal({graded: 1, archived: 0}, Submission.reap_abandoned_vivas!)
    end
    sub.reload
    assert_predicate sub, :evaluating?
    assert sub.viva_turns.where(role: :system).where("content LIKE '%expired%'").exists?,
           "must leave the expiry system turn in the transcript"
  end

  test "reap_abandoned_vivas! archives an idle greeting-only session without grading" do
    sub = make_abandoned_viva(with_student_turn: false)
    assert_no_enqueued_jobs(only: Llm::VivaGradeAssistJob) do
      assert_equal({graded: 0, archived: 1}, Submission.reap_abandoned_vivas!)
    end
    sub.reload
    assert_predicate sub, :submitted?
    assert sub.viva_archived_at.present?, "greeting-only session must be archived, not graded"
  end

  test "reap_abandoned_vivas! leaves sessions with recent turn activity alone" do
    sub = make_abandoned_viva(with_student_turn: true)
    sub.viva_turns.create!(role: :student, status: :ok, content: 'still here') # fresh updated_at
    assert_equal({graded: 0, archived: 0}, Submission.reap_abandoned_vivas!)
    assert_predicate sub.reload, :submitted?
  end

  test "reap_abandoned_vivas! skips sessions with a processing turn (fail_stale! owns those)" do
    sub = make_abandoned_viva(with_student_turn: true)
    t = sub.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    stamp_updated_at(t, Time.zone.now - 25.hours)
    assert_equal({graded: 0, archived: 0}, Submission.reap_abandoned_vivas!)
    assert_predicate sub.reload, :submitted?
  end

  test "fail_stale_viva_evaluating! ignores non-viva submissions even if evaluating and stale" do
    sub = submissions(:add1_by_admin)
    sub.update_columns(status: Submission.statuses[:evaluating])
    stamp_updated_at(sub, 1.hour.ago)

    count = Submission.fail_stale_viva_evaluating!
    sub.reload

    assert_equal 0, count
    assert_predicate sub, :evaluating?
  end

  test "fail_stale_viva_evaluating! threshold is configurable" do
    sub = make_viva_submission(status: :evaluating)
    stamp_updated_at(sub, 5.minutes.ago)

    # Default threshold (20 min) — too fresh.
    assert_equal 0, Submission.fail_stale_viva_evaluating!

    # Tighter threshold — now stale.
    count = Submission.fail_stale_viva_evaluating!(threshold: 1.minute)
    assert_equal 1, count
  end

  test "stale_evaluating scope matches what fail_stale_viva_evaluating! would sweep" do
    stale = make_viva_submission(status: :evaluating)
    stamp_updated_at(stale, 21.minutes.ago)
    fresh = make_viva_submission(status: :evaluating)

    assert_includes Submission.stale_evaluating, stale
    assert_not_includes Submission.stale_evaluating, fresh
  end
end
