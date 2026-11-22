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

  # --- max_score_report ---

  test "max_score_report floors final_score at zero when assist cost exceeds the full score" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 100)
    2.times do |i|
      sub.comments.create!(user: users(:john), kind: 'llm_assist', status: 'ok', cost: 60,
                           title: "Assistance #{i}", body: 'hint')
    end
    records = Submission.where(id: sub.id)
                        .max_score_report([sub.problem], sub.submitted_at - 1.day, sub.submitted_at + 1.day)
    row = records.to_a.find { |r| r.sub_id == sub.id }
    assert_equal 120.0, row.llm_cost.to_f
    result = Submission.calculate_max_score(records, [users(:john)], [sub.problem])
    assert_equal 0, result[:score]['john']["final_score_#{sub.problem_id}"].to_f
  end

  test "calculate_max_score applies a deduction cap and reports the raw cost beside it" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 90)
    sub.comments.create!(user: users(:john), kind: 'llm_assist', status: 'ok', cost: 60, title: 'a', body: 'hint')
    records = Submission.where(id: sub.id)
                        .max_score_report([sub.problem], sub.submitted_at - 1.day, sub.submitted_at + 1.day)
    row = Submission.calculate_max_score(records, [users(:john)], [sub.problem], deduction_cap: 30)[:score]['john']
    assert_equal 70, row["final_score_#{sub.problem_id}"].to_f
    assert_equal 30, row["total_cost_#{sub.problem_id}"].to_f
    assert_equal 60, row["raw_cost_#{sub.problem_id}"].to_f
  end

  # --- llm_assist_refusal (picker guards) ---

  def assist_comment(sub, status:, model: 'm', cost: 10)
    sub.comments.create!(user: sub.user, kind: 'llm_assist', status: status, llm_model: model, cost: cost, title: 't', body: 'b')
  end

  test "llm_assist_refusal is nil for a fresh, partially scored submission" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 40)
    assert_nil sub.llm_assist_refusal('m')
  end

  test "llm_assist_refusal while an earlier request is still processing" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 40)
    assist_comment(sub, status: 'processing', cost: 0)
    assert_match(/still running/i, sub.llm_assist_refusal('other'))
  end

  test "llm_assist_refusal when the same model already answered this submission" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 40)
    assist_comment(sub, status: 'ok', model: 'm')
    assert_match(/already answered/i, sub.llm_assist_refusal('m'))
    assert_nil sub.llm_assist_refusal('other')
  end

  test "llm_assist_refusal at full score" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 100)
    assert_match(/full score/i, sub.llm_assist_refusal('m'))
  end

  test "llm_assist_refusal once the user's assist spend on the problem reaches the full score" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 40)
    earlier = Submission.new(user: sub.user, problem: sub.problem, language: sub.language, source: 'x',
                             submitted_at: sub.submitted_at - 1.hour)
    earlier.save!(validate: false)
    assist_comment(earlier, status: 'ok', model: 'a', cost: 60)
    assist_comment(earlier, status: 'ok', model: 'b', cost: 40)
    assert_match(/spent/i, sub.llm_assist_refusal('m'))
  end

  # --- spending limit (HelpDeduction, spec 2026-11-21) ---

  def spend_ai(sub, cost, model: 'a')
    earlier = Submission.new(user: sub.user, problem: sub.problem, language: sub.language, source: 'x',
                             submitted_at: sub.submitted_at - 1.hour)
    earlier.save!(validate: false)
    assist_comment(earlier, status: 'ok', model: model, cost: cost)
  end

  test "the spending-limit refusal names the limit" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 40)
    spend_ai(sub, 100)
    assert_equal "already spent 100 of the 100 points of AI help allowed on this problem", sub.llm_assist_refusal('m')
  ensure
    reset_grader_config_cache
  end

  test "the site spending limit can be raised above 100" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 40)
    spend_ai(sub, 120)
    assert_match(/of the 100 points/, sub.llm_assist_refusal('m'))
    set_grader_config('system.llm_assist_spending_limit', 150)
    assert_nil sub.llm_assist_refusal('m')
  ensure
    reset_grader_config_cache
  end

  test "a running contest's spending limit applies, above or below the site's" do
    set_grader_config('system.mode', 'contest')
    sub = submissions(:add1_by_james)                 # james is in contest_a, which holds prob_add
    sub.update_columns(points: 40)
    spend_ai(sub, 100)
    contests(:contest_a).update!(assist_spending_limit: 150)
    assert_nil sub.llm_assist_refusal('m')
    contests(:contest_a).update!(assist_spending_limit: 50)
    assert_match(/already spent 100 of the 50 points/, sub.llm_assist_refusal('m'))
  ensure
    reset_grader_config_cache
  end

  test "with two running contests the largest spending limit wins, a blank one meaning the site's" do
    set_grader_config('system.mode', 'contest')
    sub = submissions(:add1_by_james).dup
    sub.assign_attributes(user: users(:jack), problem: problems(:easy), points: 40, number: nil)
    sub.save!(validate: false)                        # easy is in contest_a and contest_b, jack in both
    contests(:contest_a).update!(assist_spending_limit: 50)
    spend_ai(sub, 60)
    assert_nil sub.llm_assist_refusal('m'), "contest_b is blank, so the site's 100 applies"
    spend_ai(sub, 40, model: 'b')
    assert_match(/of the 100 points/, sub.llm_assist_refusal('m'))
  ensure
    reset_grader_config_cache
  end

  test "a spending limit of 0 refuses with a plain message" do
    sub = submissions(:add1_by_john)
    sub.update_columns(points: 40)
    set_grader_config('system.llm_assist_spending_limit', 0)
    assert_equal "no AI help is allowed on this problem", sub.llm_assist_refusal('m')
  ensure
    reset_grader_config_cache
  end

  test "judge_backlog lists ungraded non-viva submissions only" do
    viva = Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
    ungraded = Submission.create!(user: users(:john), problem: problems(:prob_add), language: languages(:Language_c),
                                  source: "int main() { return 0; }", submitted_at: Time.zone.now)
    graded = Submission.create!(user: users(:john), problem: problems(:prob_add), language: languages(:Language_c),
                                source: "int main() { return 1; }", submitted_at: Time.zone.now, graded_at: Time.zone.now)
    viva_sub = Submission.create!(user: users(:john), problem: problems(:prob_viva), language: viva,
                                  status: :submitted, submitted_at: Time.zone.now)

    assert_includes Submission.judge_backlog, ungraded
    assert_not_includes Submission.judge_backlog, graded
    assert_not_includes Submission.judge_backlog, viva_sub
  end

  # --- grade history: adopt_viva_grade! / regrade_viva! (spec 2026-09-23-viva-grade-history-design) ---

  def make_run(sub, total:, superseded_at: nil, reason: nil, graded_at: Time.zone.now)
    sub.viva_grades.create!(total_points: total, narrative: "n#{total}", score_json: {'a' => total}.to_json,
                            llm_model: 'test-model', graded_at: graded_at, superseded_at: superseded_at,
                            superseded_reason: reason)
  end

  test "adopt_viva_grade! makes the run current and copies its result onto the submission" do
    sub = make_viva_submission(status: :done)
    old = make_run(sub, total: 40, graded_at: 2.hours.ago)
    sub.update!(points: 40, graded_at: 2.hours.ago, grader_comment: Submission::VIVA_RESULT_MARKER)
    new_run = make_run(sub, total: 70, superseded_at: Time.zone.now)

    sub.adopt_viva_grade!(new_run)

    sub.reload; old.reload; new_run.reload
    assert new_run.current?
    assert_equal new_run, sub.viva_grade
    assert_equal 70, sub.points
    assert_equal 'done', sub.status
    assert_in_delta new_run.graded_at, sub.graded_at, 1
    assert_equal Submission::VIVA_RESULT_MARKER, sub.grader_comment
    assert_equal 'replaced', old.superseded_reason
    assert_equal new_run.id, old.superseded_by_id
  end

  test "adopt_viva_grade! with reason reverted labels the displaced run reverted and clears the re-adopted row" do
    sub = make_viva_submission(status: :done)
    old = make_run(sub, total: 40, superseded_at: 1.hour.ago, reason: 'replaced')
    cur = make_run(sub, total: 70)
    old.update!(superseded_by_id: cur.id)
    sub.update!(points: 70)

    sub.adopt_viva_grade!(old, reason: 'reverted')

    old.reload; cur.reload
    assert old.current?
    assert_nil old.superseded_reason
    assert_nil old.superseded_by_id
    assert_equal 'reverted', cur.superseded_reason
    assert_equal old.id, cur.superseded_by_id
    assert_equal 40, sub.reload.points
  end

  test "adopt_viva_grade! labels a displaced FAILED current run error and refuses to adopt a failed run" do
    sub = make_viva_submission(status: :grader_error)
    failed = sub.viva_grades.create!(llm_response_raw: 'prose')      # legacy shape: a failed row that is still current
    good = make_run(sub, total: 65, superseded_at: Time.zone.now)
    sub.adopt_viva_grade!(good)
    assert_equal 'error', failed.reload.superseded_reason
    assert_equal good.id, failed.superseded_by_id
    assert_equal 'done', sub.reload.status
    assert_equal 65, sub.points
    assert_raises(ArgumentError) { sub.adopt_viva_grade!(failed) }
  end

  test "adopt_viva_grade! refuses a run of another submission" do
    a = make_viva_submission(status: :done)
    b = make_viva_submission(status: :done, user: users(:james))
    run = make_run(b, total: 50)
    assert_raises(ArgumentError) { a.adopt_viva_grade!(run) }
  end

  test "valid_viva_grade? is true only with a current run that has points" do
    sub = make_viva_submission(status: :done)
    refute sub.valid_viva_grade?
    sub.viva_grades.create!(superseded_at: Time.zone.now, superseded_reason: 'error', error: 'x')
    refute sub.valid_viva_grade?
    make_run(sub, total: 30)
    assert sub.valid_viva_grade?
  end

  test "regrade_viva! leaves a graded submission untouched and enqueues the job with the given options" do
    sub = make_viva_submission(status: :done)
    make_run(sub, total: 40)
    sub.update!(points: 40, grader_comment: Submission::VIVA_RESULT_MARKER)
    assert_enqueued_with(job: Llm::VivaGradeAssistJob,
                         args: [sub, {model: 'gemini-x', never_lower: false, requested_by_id: users(:admin).id, batch_id: 'b1'}]) do
      sub.regrade_viva!(model: 'gemini-x', never_lower: false, requested_by: users(:admin), batch_id: 'b1')
    end
    sub.reload
    assert_equal 'done', sub.status
    assert_equal 40, sub.points
    assert_equal Submission::VIVA_RESULT_MARKER, sub.grader_comment
  end

  test "regrade_viva! sends a submission without a valid grade back to evaluating" do
    sub = make_viva_submission(status: :grader_error)
    sub.update!(grader_comment: 'Grader error: prose')
    assert_enqueued_with(job: Llm::VivaGradeAssistJob, args: [sub, {never_lower: true}]) do
      sub.regrade_viva!
    end
    sub.reload
    assert_equal 'evaluating', sub.status
    assert_nil sub.points
    assert_nil sub.grader_comment
  end

  test "regrade_viva! refuses an open interview and a non-viva submission" do
    open_session = make_viva_submission(status: :submitted)
    assert_raises(Submission::NotRegradable) { open_session.regrade_viva! }
    assert_raises(Submission::NotRegradable) { submissions(:add1_by_admin).regrade_viva! }
  end

  test "regrade_viva! files a failed run that is still current as error before re-grading" do
    sub = make_viva_submission(status: :grader_error)
    legacy = sub.viva_grades.create!(llm_response_raw: 'prose', graded_at: 1.hour.ago)   # legacy shape: failed and current
    sub.regrade_viva!
    legacy.reload
    refute legacy.current?
    assert_equal 'error', legacy.superseded_reason
    assert_nil sub.reload.viva_grade
    assert_equal 'evaluating', sub.status
  end

  test "regrade_viva! queues a batch run at priority 10 and a Re-run at the default priority" do
    sub = make_viva_submission(status: :done)
    make_run(sub, total: 40)
    clear_enqueued_jobs
    sub.regrade_viva!(batch_id: 'b1')
    sub.regrade_viva!
    jobs = enqueued_jobs.select { |j| j[:job] == Llm::VivaGradeAssistJob }
    assert_equal 2, jobs.size
    assert_equal 10, jobs.first[:priority]
    assert_nil jobs.last[:priority]
  end

  test "regrade_viva! checks the status after taking the lock" do
    sub = make_viva_submission(status: :done)
    Submission.where(id: sub.id).update_all(status: Submission.statuses[:submitted])   # reopened behind this handle's back
    assert_equal 'done', sub.status
    assert_raises(Submission::NotRegradable) { sub.regrade_viva! }
    assert_no_enqueued_jobs(only: Llm::VivaGradeAssistJob)
  end

  test "adopt_viva_grade! returns the displaced run read under the lock" do
    sub = make_viva_submission(status: :done)
    first = make_run(sub, total: 40)
    stale_handle = Submission.find(sub.id)
    stale_handle.viva_grade                                        # caches `first`
    second = make_run(sub, total: 50, superseded_at: Time.zone.now)
    sub.adopt_viva_grade!(second)                                  # a re-run lands meanwhile
    third = make_run(sub, total: 45, superseded_at: Time.zone.now)
    assert_equal second, stale_handle.adopt_viva_grade!(third, reason: 'reverted')
    assert_equal 'reverted', second.reload.superseded_reason
    assert_equal 'replaced', first.reload.superseded_reason
    assert_nil sub.adopt_viva_grade!(third), 'nothing displaced when the run is already current'
  end

  test "fail_stale_viva_evaluating! sweeps a stale evaluating submission whose only grade rows are superseded" do
    sub = make_viva_submission(status: :evaluating)
    sub.viva_grades.create!(superseded_at: Time.zone.now, superseded_reason: 'error', error: 'x')
    stamp_updated_at(sub, 21.minutes.ago)
    assert_equal 1, Submission.fail_stale_viva_evaluating!
    assert_predicate sub.reload, :grader_error?
  end

  # --- "Allow another attempt" (Submission#grant_viva_retake!) ---

  test "grant_viva_retake! archives an open session, stamps who granted it, and is idempotent" do
    admin = users(:admin)
    sub = make_viva_submission(status: :submitted)
    assert_equal :granted, sub.grant_viva_retake!(by: admin)
    sub.reload
    assert sub.viva_archived_at.present?
    assert sub.viva_retake_granted_at.present?
    assert_equal admin, sub.viva_retake_granted_by

    first = sub.viva_retake_granted_at
    assert_equal :already, sub.grant_viva_retake!(by: admin)
    assert_in_delta first, sub.reload.viva_retake_granted_at, 0.001
  end

  test "grant_viva_retake! keeps an earlier archive time and refuses test-drives and code submissions" do
    archived_at = 2.hours.ago
    sub = make_viva_submission(status: :done)
    sub.update!(viva_archived_at: archived_at)
    assert_equal :granted, sub.grant_viva_retake!(by: users(:admin))
    assert_in_delta archived_at, sub.reload.viva_archived_at, 1

    drive = make_viva_submission(status: :done)
    drive.update!(test_drive: true)
    assert_equal :test_drive, drive.grant_viva_retake!(by: users(:admin))
    assert_nil drive.reload.viva_retake_granted_at

    assert_equal :not_viva, submissions(:add1_by_john).grant_viva_retake!(by: users(:admin))
  end
end
