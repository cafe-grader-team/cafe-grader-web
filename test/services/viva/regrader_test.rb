require "test_helper"

# Batch regrade (spec docs/superpowers/specs/2026-09-23-viva-grade-history-design.md,
# "bin/rails viva:regrade"). No LLM call is made here: apply! only enqueues.
class Viva::RegraderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def viva_language
    Language.find_or_create_by!(name: 'viva') { |l| l.pretty_name = 'Viva Exam' }
  end

  setup do
    @problem = problems(:prob_viva)
    @problem.update!(viva_prompt: "# Rubric\nBe fair.")
    @rubric = Llm::VivaGradeAssist.rubric_version_for(@problem)
    @io = StringIO.new
  end

  # A session of @problem. rubric: :current (graded under today's rubric),
  # :stale (an earlier rubric) or nil (legacy row, never versioned).
  def graded(user:, total: 50, rubric: :stale, archived: false, test_drive: false, submitted_at: Time.zone.now, status: :done)
    sub = Submission.create!(user: user, problem: @problem, language: viva_language, status: status,
                             points: (status == :done ? total : nil), submitted_at: submitted_at,
                             viva_archived_at: (archived ? Time.zone.now : nil), test_drive: test_drive)
    if status == :done
      sub.viva_grades.create!(total_points: total, graded_at: submitted_at + 10.minutes, llm_model: 'old', cost: 0.01,
                              rubric_version: {current: @rubric, stale: 'stale-rubric', nil => nil}[rubric])
    end
    sub
  end

  def regrader(**opts) = Viva::Regrader.new(problem: @problem, io: @io, **opts)

  test "plan targets stale and legacy grades, retries grader errors, skips up-to-date and open sessions" do
    stale  = graded(user: users(:john))
    legacy = graded(user: users(:james), rubric: nil)
    graded(user: users(:jack), rubric: :current)
    failed = graded(user: users(:mary), status: :grader_error)
    graded(user: users(:reba), status: :submitted)
    plan = regrader.plan
    assert_equal [stale, legacy, failed].map(&:id).sort, plan.targets.map(&:id).sort
    assert_equal 1, plan.retries
    assert_equal 1, plan.up_to_date
    assert_equal 1, plan.open
    assert_equal @rubric, plan.rubric_version
    assert_in_delta 0.03, plan.estimated_cost, 0.001   # mean past cost 0.01 x 3 targets
    assert_equal 3, plan.cost_samples
  end

  test "plan counts a session with a lower run under the current rubric as up to date, however stale its current grade" do
    sub = graded(user: users(:john), total: 60)                              # current grade: stale rubric
    sub.viva_grades.create!(total_points: 45, graded_at: Time.zone.now, superseded_at: Time.zone.now,
                            superseded_reason: 'lower', rubric_version: @rubric, batch_id: 'earlier')
    failed_only = graded(user: users(:james))                                # an error run under today's rubric is no grade
    failed_only.viva_grades.create!(superseded_at: Time.zone.now, superseded_reason: 'error', error: 'x', rubric_version: @rubric)
    plan = regrader.plan
    assert_equal [failed_only.id], plan.targets.map(&:id)
    assert_equal 1, plan.up_to_date
    assert_equal [sub.id, failed_only.id].sort, regrader(all: true).plan.targets.map(&:id).sort, 'ALL=1 still overrides'
  end

  test "plan targets a done session whose only run under the current rubric was reverted or filed as error" do
    reverted = graded(user: users(:john), total: 60)                          # current grade: stale rubric
    reverted.viva_grades.create!(total_points: 55, graded_at: Time.zone.now, superseded_at: Time.zone.now,
                                 superseded_reason: 'reverted', rubric_version: @rubric, batch_id: 'earlier')
    errored = graded(user: users(:james), total: 60)                          # current grade: stale rubric
    errored.viva_grades.create!(total_points: 58, graded_at: Time.zone.now, superseded_at: Time.zone.now,
                                superseded_reason: 'error', error: 'adopt failed', rubric_version: @rubric, batch_id: 'earlier')
    plan = regrader.plan
    assert_equal [reverted.id, errored.id].sort, plan.targets.map(&:id).sort
    assert_equal 0, plan.up_to_date
  end

  test "plan targets a done session that has no grade row at all" do
    bare = Submission.create!(user: users(:john), problem: @problem, language: viva_language, status: :done,
                              points: nil, submitted_at: Time.zone.now)
    assert_equal [bare.id], regrader.plan.targets.map(&:id)
  end

  test "the cost estimate is unknown when no past run has a cost" do
    sub = graded(user: users(:john))
    sub.viva_grades.update_all(cost: nil)
    plan = regrader.report
    assert_nil plan.estimated_cost
    assert_equal 0, plan.cost_samples
    assert_includes @io.string, 'unknown (no past run has a cost)'
  end

  test "the dry run warns how many viva sessions are open site-wide" do
    graded(user: users(:john))
    graded(user: users(:james), status: :submitted)
    graded(user: users(:jack), status: :submitted, archived: true)          # archived: not live
    regrader.report
    assert_includes @io.string, 'open viva sessions right now: 1 (batch runs queue behind their turns)'
  end

  test "ALL regrades up-to-date grades too; archived attempts are included; test-drives are not" do
    fresh    = graded(user: users(:john), rubric: :current)
    archived = graded(user: users(:james), archived: true)
    drive    = graded(user: users(:admin), test_drive: true)
    plan = regrader(all: true).plan
    assert_equal [fresh, archived].map(&:id).sort, plan.targets.map(&:id).sort
    assert_equal 1, plan.archived
    refute_includes plan.targets.map(&:id), drive.id
  end

  test "LIMIT takes the first n targets by id" do
    a = graded(user: users(:john))
    b = graded(user: users(:james))
    graded(user: users(:jack))
    assert_equal [a.id, b.id], regrader(limit: 2).plan.targets.map(&:id)
  end

  test "a non-viva problem and a viva problem without a briefing are refused" do
    assert_raises(ArgumentError) { Viva::Regrader.new(problem: problems(:prob_add), io: @io) }
    @problem.update_columns(viva_prompt: nil)
    assert_raises(ArgumentError) { Viva::Regrader.new(problem: @problem.reload, io: @io) }
  end

  test "CONTEST narrows to the contest's enrolled users inside its window and rejects a foreign problem" do
    contest = contests(:contest_a)                      # james and jack enrolled; window 1h ago .. 3h from now
    assert_raises(ArgumentError) { regrader(contest: contest) }
    ContestProblem.create!(contest: contest, problem: @problem, number: 9, enabled: true)
    in_window = graded(user: users(:james))
    graded(user: users(:jack), submitted_at: 2.days.ago)     # enrolled, but started outside the window
    graded(user: users(:john))                               # not enrolled
    plan = regrader(contest: contest).plan
    assert_equal [in_window.id], plan.targets.map(&:id)
    assert_equal contest, plan.contest
  end

  test "find_problem and find_contest accept an id or a name" do
    assert_equal @problem, Viva::Regrader.find_problem(@problem.id.to_s)
    assert_equal @problem, Viva::Regrader.find_problem(@problem.name)
    assert_nil Viva::Regrader.find_problem('no-such-problem')
    assert_equal contests(:contest_a), Viva::Regrader.find_contest('contest_a')
  end

  test "report prints the dry run and changes nothing" do
    graded(user: users(:john))
    assert_no_enqueued_jobs { regrader.report }
    out = @io.string
    assert_includes out, 'DRY RUN'
    assert_includes out, @problem.name
    assert_includes out, 'never-lower'
    assert_includes out, 'targets    1'
  end

  test "apply! queues one run per target with the batch id and writes one audit row" do
    a = graded(user: users(:john))
    b = graded(user: users(:james), status: :grader_error)
    Current.actor_note = 'Rake: viva:regrade test'
    batch_id = plan = nil
    assert_enqueued_jobs 2, only: Llm::VivaGradeAssistJob do
      batch_id, plan = regrader(model: 'gemini-x', never_lower: false).apply!(now: Time.zone.local(2026, 9, 23, 18, 0, 0))
    end
    assert_equal "regrade-#{@problem.id}-20260923T180000", batch_id
    assert_equal 2, plan.targets.size
    audit = AuditLog.where(auditable: @problem, action: 'viva_regrade').order(:id).last
    assert_equal batch_id, audit.object_changes.dig('batch_id', 1)
    assert_equal 'gemini-x', audit.object_changes.dig('model', 1)
    assert_equal false, audit.object_changes.dig('never_lower', 1)
    assert_equal @rubric, audit.object_changes.dig('rubric_version', 1)
    assert_equal [a.id, b.id].sort, audit.object_changes.dig('submission_ids', 1).sort
    assert_equal 'Rake: viva:regrade test', audit.actor_note
    assert_equal 'evaluating', b.reload.status, 'a grader_error retry goes through the evaluating path'
    assert_equal 'done', a.reload.status, 'a graded session is untouched until its new run is adopted'
    assert_includes @io.string, "queued 2 run(s) as batch #{batch_id}"
  ensure
    Current.actor_note = nil
  end

  test "apply! skips a target that became unregradable after the plan and queues the rest at batch priority" do
    a = graded(user: users(:john))
    b = graded(user: users(:james))
    r = regrader
    planned = r.plan
    Submission.where(id: b.id).update_all(status: Submission.statuses[:submitted])   # reopened after the plan
    r.define_singleton_method(:plan) { planned }
    batch_id = nil
    assert_enqueued_jobs 1, only: Llm::VivaGradeAssistJob do
      batch_id, _p = r.apply!(now: Time.zone.local(2026, 9, 23, 18, 0, 0))
    end
    assert_match(/SKIP     ##{b.id}: the interview is still open/, @io.string)
    assert_equal 10, enqueued_jobs.last[:priority]
    audit = Viva::Regrader.find_batch_audit(batch_id)
    assert_equal [a.id], audit.object_changes.dig('submission_ids', 1)
  end

  test "apply! still writes the audit row for the runs queued before an unexpected error" do
    a = graded(user: users(:john))
    b = graded(user: users(:james))
    r = regrader
    planned = r.plan
    boom = planned.targets.find { |t| t.id == b.id }
    def boom.regrade_viva!(**) = raise(ActiveRecord::StatementInvalid, 'lost connection')
    r.define_singleton_method(:plan) { planned }
    assert_raises(ActiveRecord::StatementInvalid) { r.apply!(now: Time.zone.local(2026, 9, 23, 18, 0, 0)) }
    audit = Viva::Regrader.find_batch_audit("regrade-#{@problem.id}-20260923T180000")
    assert_equal [a.id], audit.object_changes.dig('submission_ids', 1)
  end

  test "apply! writes no audit row when nothing was queued" do
    graded(user: users(:john), rubric: :current)
    regrader.apply!
    refute AuditLog.where(auditable: @problem, action: 'viva_regrade').exists?
  end

  # What the grader service would leave behind for a batch: an adopted run
  # for `a` (40 → 60), a lower run for `b` (45 vs 50 kept), an error run for
  # `c`, and nothing yet for `d`.
  def batch_with_outcomes
    a = graded(user: users(:john), total: 40)
    b = graded(user: users(:james), total: 50)
    c = graded(user: users(:jack), total: 30)
    d = graded(user: users(:mary), total: 20)
    batch_id, _plan = regrader.apply!(now: Time.zone.local(2026, 9, 23, 18, 0, 0))
    now = Time.zone.now
    new_a = a.viva_grades.create!(total_points: 60, graded_at: now, superseded_at: now, batch_id: batch_id, llm_model: 'new')
    a.adopt_viva_grade!(new_a)
    b.viva_grades.create!(total_points: 45, graded_at: now, superseded_at: now, superseded_reason: 'lower', batch_id: batch_id, llm_model: 'new')
    VivaGrade.record_failure!(c, error: 'boom', batch_id: batch_id, model: 'new')
    [batch_id, a, b, c, d]
  end

  test "status reports old, new and final per target, the counts and the movement" do
    batch_id, a, b, c, d = batch_with_outcomes
    st = Viva::Regrader.status(batch_id)
    by = st.rows.index_by(&:submission_id)
    assert_equal ['adopted', 40.0, 60.0, 60.0], [by[a.id].outcome, by[a.id].old, by[a.id].new, by[a.id].final]
    assert_equal ['lower',   50.0, 45.0, 50.0], [by[b.id].outcome, by[b.id].old, by[b.id].new, by[b.id].final]
    assert_equal ['error',   30.0, nil,  30.0], [by[c.id].outcome, by[c.id].old, by[c.id].new, by[c.id].final]
    assert_equal ['pending', 20.0, nil,  20.0], [by[d.id].outcome, by[d.id].old, by[d.id].new, by[d.id].final]
    assert_equal 'john', by[a.id].login
    s = st.summary
    assert_equal({'adopted' => 1, 'lower' => 1, 'error' => 1, 'pending' => 1}, s[:counts])
    assert_in_delta 35.0, s[:mean_old], 0.001
    assert_in_delta 40.0, s[:mean_final], 0.001
    assert_equal({up: 1, equal: 3, down: 0}, s[:movement])
    csv = st.to_csv
    assert_equal 'submission_id,login,archived,old,new,final,outcome', csv.lines.first.chomp
    assert_equal 5, csv.lines.size
    st.print(@io)
    assert_includes @io.string, 'adopted=1 lower=1 error=1 reverted=0 replaced=0 pending=1 undecided=0'
    assert_equal @problem, st.problem
  end

  test "status reports a batch run later displaced by a manual re-run as replaced, old = what it displaced" do
    batch_id, a, _b, _c, _d = batch_with_outcomes            # a: 40 -> 60 by the batch
    manual = a.viva_grades.create!(total_points: 75, graded_at: Time.zone.now, superseded_at: Time.zone.now, llm_model: 'manual')
    a.adopt_viva_grade!(manual)
    row = Viva::Regrader.status(batch_id).rows.find { |r| r.submission_id == a.id }
    assert_equal ['replaced', 40.0, 60.0, 75.0], [row.outcome, row.old, row.new, row.final]
  end

  test "status reports a written but undecided run as undecided" do
    a = graded(user: users(:john), total: 40)
    batch_id, _plan = regrader.apply!(now: Time.zone.local(2026, 9, 23, 18, 0, 0))
    a.viva_grades.create!(total_points: 55, graded_at: Time.zone.now, superseded_at: Time.zone.now, batch_id: batch_id)
    st = Viva::Regrader.status(batch_id)
    row = st.rows.first
    assert_equal ['undecided', 40.0, 55.0, 40.0], [row.outcome, row.old, row.new, row.final]
    st.print(@io)
    assert_includes @io.string, 'undecided=1'
  end

  test "status refuses an unknown batch" do
    assert_raises(ArgumentError) { Viva::Regrader.status("regrade-#{@problem.id}-19700101T000000") }
    assert_raises(ArgumentError) { Viva::Regrader.status('nonsense') }
  end

  test "revert re-adopts the replaced runs, leaves lower and error runs alone, and is report-only without apply" do
    batch_id, a, b, c, _d = batch_with_outcomes
    counts = Viva::Regrader.revert(batch_id, apply: false, io: @io)
    assert_equal({reverted: 1}, counts)
    assert_equal 60, a.reload.points, 'dry run changes nothing'
    refute AuditLog.where(auditable: @problem, action: 'viva_regrade_revert').exists?

    counts = Viva::Regrader.revert(batch_id, apply: true, io: @io)
    assert_equal({reverted: 1}, counts)
    a.reload
    assert_equal 40, a.points
    assert_equal 40, a.viva_grade.total_points
    displaced = a.viva_grades.where(batch_id: batch_id).first
    assert_equal 'reverted', displaced.superseded_reason
    assert_equal a.viva_grade.id, displaced.superseded_by_id
    assert_equal 50, b.reload.points
    assert_equal 30, c.reload.points
    assert AuditLog.where(auditable: @problem, action: 'viva_regrade_revert').exists?
    assert_equal({}, Viva::Regrader.revert(batch_id, apply: true, io: @io), 'nothing left to revert')
    assert_equal 'reverted', Viva::Regrader.status(batch_id).rows.find { |r| r.submission_id == a.id }.outcome
  end

  test "revert keeps a run that has no earlier valid grade behind it" do
    a = graded(user: users(:john), status: :grader_error)
    batch_id, _plan = regrader.apply!(now: Time.zone.local(2026, 9, 23, 18, 0, 0))
    run = a.viva_grades.create!(total_points: 65, graded_at: Time.zone.now, superseded_at: Time.zone.now, batch_id: batch_id, llm_model: 'new')
    a.adopt_viva_grade!(run)
    assert_equal({kept: 1}, Viva::Regrader.revert(batch_id, apply: true, io: @io))
    assert_equal 65, a.reload.points
  end

  test "revert refuses a batch whose problem no longer exists" do
    batch_id, _a, _b, _c, _d = batch_with_outcomes
    @problem.grounding_materials.clear                 # HABTM join row has an FK on problem_id
    Problem.where(id: @problem.id).delete_all          # the audit row outlives its problem by design
    err = assert_raises(ArgumentError) { Viva::Regrader.revert(batch_id, apply: true, io: @io) }
    assert_match(/no longer exists/, err.message)
    refute AuditLog.where(action: 'viva_regrade_revert').exists?
  end
end
