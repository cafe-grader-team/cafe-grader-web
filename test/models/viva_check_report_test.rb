require "test_helper"

class VivaCheckReportTest < ActiveSupport::TestCase
  RUBRIC = "# Briefing\nAsk about a and b.\n\n# Rubric\n\n- a (20): first\n- b (80): second\n".freeze

  setup do
    @contest = contests(:contest_a)              # start 1h ago, stop 3h from now; problems prob_add, easy
    @problem = problems(:prob_viva)
    @problem.update!(viva_prompt: RUBRIC)
    ContestProblem.create!(contest: @contest, problem: @problem, number: 3, enabled: true)
    @lang = Language.find_or_create_by!(name: 'viva') { |l| l.pretty_name = 'Viva Exam' }
    @now  = Time.zone.now
  end

  # A viva session saved without the submit-permission check: system turn,
  # greeting answered in 4 s, then `answers` student answers.
  def session_for(user, problem: @problem, answers: 1, status: :submitted, submitted_at: @now - 20.minutes, **attrs)
    s = Submission.new(user: user, problem: problem, language: @lang, status: status,
                       submitted_at: submitted_at, **attrs)
    s.save!(validate: false)
    s.viva_turns.create!(role: :system, status: :ok, content: '(interview start)')
    s.viva_turns.create!(role: :assistant, status: :ok, content: 'Q?',
                         created_at: submitted_at, updated_at: submitted_at + 4.seconds)
    answers.times { s.viva_turns.create!(role: :student, status: :ok, content: 'A') }
    s
  end

  def grade(sub, total, scores)
    VivaGrade.create!(submission: sub, total_points: total, score_json: scores.to_json,
                      llm_model: 'm', graded_at: @now)
    sub.update_columns(points: total, status: Submission.statuses[:done])
  end

  def report = VivaCheckReport.new(@contest, now: @now)

  # contest_a's fixture students are james and jack (mary and admin are its
  # editors); tests that need more student rows enrol john and reba.
  def enrol_student(user)
    ContestUser.create!(contest: @contest, user: user, role: 0, enabled: true,
                        start_offset_second: 0, extra_time_second: 0)
    user
  end

  def row_for(user, rep = report, check: 0)
    rep.checks[check].rows.find { |r| r.user_id == user.id }
  end

  test "two answered sessions without a grant are flagged Retook, with the grant on the latest" do
    first = session_for(users(:james), answers: 4)
    grade(first, 74, a: 14, b: 60)
    second = session_for(users(:james), answers: 4, submitted_at: @now - 5.minutes)
    grade(second, 83, a: 18, b: 65)

    row = row_for(users(:james))
    assert_equal [:retook], row.flags
    assert_equal second.id, row.grantable_id
    assert_equal 83.0, row.best
    assert_equal 2, row.answered
    assert row.needs_action?
    assert_equal 1, report.needs_action_count
  end

  test "a grant clears Retook and the granted session stays listed" do
    first = session_for(users(:james))
    grade(first, 74, a: 14, b: 60)
    first.grant_viva_retake!(by: users(:admin))
    session_for(users(:james), submitted_at: @now - 5.minutes)

    row = row_for(users(:james))
    refute_includes row.flags, :retook
    assert_equal 2, row.sessions.size
  end

  test "live flags: waiting for a reply, reply failed, no answer yet" do
    waiting = session_for(users(:james))
    waiting.viva_turns.create!(role: :assistant, status: :processing, content: nil, created_at: @now - 2.minutes)
    failed = session_for(users(:jack))
    failed.viva_turns.create!(role: :assistant, status: :error, content: 'LLM error')
    session_for(enrol_student(users(:john)), answers: 0, submitted_at: @now - 10.minutes)

    assert_includes row_for(users(:james)).flags, :waiting_reply
    assert_includes row_for(users(:jack)).flags, :reply_failed
    assert_equal [:no_answer_yet], row_for(users(:john)).flags
    refute row_for(users(:john)).needs_action?
  end

  test "after-exam flags: left unfinished, grading failed, grade mismatch, short but high, ended early, rule flag" do
    session_for(users(:james), viva_archived_at: @now - 1.minute)                     # archived mid-interview
    jack = session_for(users(:jack))
    jack.update_columns(status: Submission.statuses[:grader_error])
    john = session_for(enrol_student(users(:john)), answers: 2)
    grade(john, 90, a: 30, b: 60)                                                    # a above its 20
    reba = session_for(enrol_student(users(:reba)), answers: 5)
    grade(reba, 70, a: 10, b: 60)
    reba.viva_turns.create!(role: :system, status: :ok, content: '(student ended the interview — grading begins)')
    reba.viva_turns.create!(role: :assistant, status: :ok, content: 'Stay on topic.', alerted: true)

    assert_equal [:left_unfinished], row_for(users(:james)).flags
    assert_equal [:grading_failed], row_for(users(:jack)).flags
    john_row = row_for(users(:john))
    assert_equal [:grade_mismatch, :short_high], john_row.flags
    assert_match(/above maximum: a 30\/20/, john_row.details[:grade_mismatch])
    assert_equal [:ended_early, :rule_flag], row_for(users(:reba)).flags
  end

  test "test-drives and sessions outside the contest window are left out" do
    session_for(users(:james), test_drive: true)
    session_for(users(:jack), submitted_at: @contest.start - 2.hours)
    assert_empty report.checks.first.rows
    assert_equal 0, report.summary[:sessions]
  end

  test "a student's sessions on two viva problems are separate rows" do
    second_viva = problems(:easy)
    second_viva.update!(compilation_type: :viva_exam, viva_prompt: RUBRIC)
    first = session_for(users(:james))
    grade(first, 74, a: 14, b: 60)
    session_for(users(:james), problem: second_viva)

    rep = report
    assert_equal 2, rep.checks.size
    first_row, second_row = [@problem, second_viva].map do |problem|
      rep.checks.find { |c| c.problem == problem }.rows.find { |r| r.user_id == users(:james).id }
    end
    assert_equal [1, 1], [first_row.sessions.size, second_row.sessions.size]
    assert_equal [:short_high], first_row.flags     # 1 answer, 74 points; no :retook across problems
    assert_empty second_row.flags
  end

  test "staff sessions are not rows and do not count: only the contest's students are checked" do
    session_for(users(:james))
    session_for(users(:mary), answers: 2)          # contest_a editor
    session_for(users(:admin), answers: 2)         # admin enrolled as a contest_a editor

    rep = report
    assert_equal [users(:james).id], rep.checks.first.rows.map(&:user_id)
    assert_nil row_for(users(:mary), rep)
    assert_equal 1, rep.summary[:sessions]
    assert_equal 1, rep.summary[:students]
  end

  test "summary counts, the greeting wait, and an unreadable rubric counting once" do
    session_for(users(:james))
    session_for(users(:jack), answers: 0, submitted_at: @now - 10.minutes)
    s = report.summary
    assert_equal 2, s[:sessions]
    assert_equal 2, s[:students]
    assert_equal 3, s[:enrolled]                 # james, jack and the disabled member
    assert_equal 1, s[:answered]
    assert_equal 2, s[:open_now]
    assert_equal 4, s[:greeting_p95]
    assert_equal 4, s[:greeting_max]
    assert_equal 0, s[:needs_action]

    @problem.update!(viva_prompt: "# Rubric\nBe fair.")
    rep = report
    refute rep.checks.first.rubric_ok?
    assert_equal 1, rep.needs_action_count
  end
end
