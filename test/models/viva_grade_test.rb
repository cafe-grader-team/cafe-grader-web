require "test_helper"

# Grade history (spec docs/superpowers/specs/2026-09-23-viva-grade-history-design.md):
# one row per grader run; superseded_at IS NULL marks the current grade.
class VivaGradeTest < ActiveSupport::TestCase
  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  def make_viva_submission(status: :done, user: users(:john))
    Submission.create!(user: user, problem: problems(:prob_viva), language: viva_language,
                       status: status, submitted_at: Time.zone.now)
  end

  # A run that produced a grade; current unless superseded_at is given.
  def make_run(sub, total:, superseded_at: nil, reason: nil, graded_at: Time.zone.now, **attrs)
    sub.viva_grades.create!(total_points: total, narrative: "n#{total}", score_json: {'a' => total}.to_json,
                            llm_model: 'test-model', graded_at: graded_at, superseded_at: superseded_at,
                            superseded_reason: reason, **attrs)
  end

  test "a submission has at most one current run" do
    sub = make_viva_submission
    make_run(sub, total: 50)
    second = sub.viva_grades.build(total_points: 60)
    refute second.valid?
    assert_includes second.errors[:submission_id], 'already has a current grade'
    second.superseded_at = Time.zone.now
    assert second.valid?, 'a non-current run may coexist with the current one'
  end

  test "viva_grade is the current run and viva_grades is the whole history" do
    sub = make_viva_submission
    old = make_run(sub, total: 40, superseded_at: 1.hour.ago, reason: 'replaced')
    cur = make_run(sub, total: 55)
    assert_equal cur, sub.reload.viva_grade
    assert_equal [old.id, cur.id], sub.viva_grades.order(:id).pluck(:id)
    assert_equal [cur], VivaGrade.current.where(submission: sub).to_a
    assert_equal [old], VivaGrade.history.where(submission: sub).to_a
    assert cur.current?
    refute old.current?
  end

  test "supersede! stamps time, reason and the replacing run" do
    sub = make_viva_submission
    old = make_run(sub, total: 40)
    new_run = make_run(sub, total: 70, superseded_at: Time.zone.now)
    old.supersede!(reason: 'replaced', by: new_run)
    old.reload
    assert old.superseded_at.present?
    assert_equal 'replaced', old.superseded_reason
    assert_equal new_run.id, old.superseded_by_id
    assert_equal new_run, old.superseded_by
  end

  test "superseded_reason accepts only the four known values" do
    sub = make_viva_submission
    assert_raises(ActiveRecord::RecordInvalid) { make_run(sub, total: 40, superseded_at: Time.zone.now, reason: 'because') }
    VivaGrade::REASONS.each do |r|
      assert make_run(sub, total: 40, superseded_at: Time.zone.now, reason: r).persisted?
    end
  end

  test "valid_grade? and failed? read total_points" do
    sub = make_viva_submission
    run = make_run(sub, total: 0)
    assert run.valid_grade?
    refute run.failed?
    bad = sub.viva_grades.create!(superseded_at: Time.zone.now, superseded_reason: 'error', error: 'x')
    refute bad.valid_grade?
    assert bad.failed?
  end

  test "record_failure! marks the run's row when one exists and creates one otherwise" do
    sub = make_viva_submission
    partial = sub.viva_grades.create!(superseded_at: Time.zone.now, llm_response_raw: '{"choices":[]}')
    VivaGrade.record_failure!(sub, error: 'grader JSON failed schema check: rubric missing', grade: partial)
    partial.reload
    assert_equal 'error', partial.superseded_reason
    assert_match(/schema check/, partial.error)
    refute partial.current?

    row = VivaGrade.record_failure!(sub, error: 'Faraday::TimeoutError: execution expired', model: 'm1',
                                    batch_id: 'b1', requested_by_id: users(:admin).id, rubric_version: 'abc')
    assert row.persisted?
    refute row.current?
    assert_equal ['error', 'm1', 'b1', users(:admin).id, 'abc'],
                 [row.superseded_reason, row.llm_model, row.batch_id, row.requested_by_id, row.rubric_version]
    assert row.graded_at.present?
    assert_match(/TimeoutError/, row.error)
    assert_nil sub.reload.viva_grade, 'a failed run is never the current grade'
  end

  test "record_failure! keeps a run non-current even when the handle's superseded_at is stale" do
    sub = make_viva_submission
    stamped = 1.hour.ago.change(usec: 0)
    run = sub.viva_grades.create!(superseded_at: stamped, llm_response_raw: '{}')
    run.superseded_at = nil                                  # in-memory only; the stored value is set
    VivaGrade.record_failure!(sub, error: 'boom', grade: run)
    run.reload
    refute run.current?
    assert_equal 'error', run.superseded_reason
    assert_in_delta stamped, run.superseded_at, 1, 'the stored time is kept, not restamped'
  end
end
