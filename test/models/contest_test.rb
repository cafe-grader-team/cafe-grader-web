require "test_helper"

class ContestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  # --- Validations ---

  test "valid contest fixture" do
    assert contests(:contest_a).valid?
  end

  test "name must be present" do
    contest = Contest.new(enabled: true)
    assert_not contest.valid?
    assert contest.errors[:name].any?
  end

  test "name must be unique" do
    contest = Contest.new(name: "contest_a")
    assert_not contest.valid?
    assert contest.errors[:name].any?
  end

  test "name must match format" do
    contest = Contest.new(name: "bad name!")
    assert_not contest.valid?
    assert contest.errors[:name].any?
  end

  # --- Scopes ---

  test "enabled scope returns only enabled contests" do
    enabled = Contest.enabled
    assert_includes enabled, contests(:contest_a)
    assert_includes enabled, contests(:contest_b)
    assert_not_includes enabled, contests(:contest_c)
  end

  # --- Methods ---

  test "add_users adds new users and skips existing" do
    contest = contests(:contest_a)
    john = users(:john)    # not in contest_a
    james = users(:james)  # already in contest_a via fixture

    result = contest.add_users(User.where(id: [john.id, james.id]))
    assert_equal 1, result.added    # john added
    assert_equal 1, result.skipped  # james skipped
  end

  test "add_users with empty returns zero" do
    contest = contests(:contest_a)
    result = contest.add_users(nil)
    assert_equal 0, result.added
  end

  test "add_problems_and_assign_number adds problems" do
    contest = contests(:contest_c)
    prob = problems(:prob_add)
    result = contest.add_problems_and_assign_number(Problem.where(id: prob.id))
    assert_equal 1, result.added
    assert_equal 0, result.skipped
  end

  test "add_problems_and_assign_number skips existing" do
    contest = contests(:contest_c)
    prob = problems(:prob_add)
    # First add prob_add
    contest.add_problems_and_assign_number(Problem.where(id: prob.id))
    contest.save!
    contest.reload

    # Try to add same problem again
    result = contest.add_problems_and_assign_number(Problem.where(id: prob.id))
    assert_equal 0, result.added
    assert_equal 1, result.skipped
  end

  test "contest_status returns correct status" do
    # contest_a started 1 hour ago, ends in 3 hours
    assert_equal :during, contests(:contest_a).contest_status

    # contest_c ended 1 day ago
    assert_equal :ended, contests(:contest_c).contest_status
  end

  test "get_next_name generates unique name" do
    contest = contests(:contest_a)
    name = contest.get_next_name
    assert_not_equal "contest_a", name
    assert_match(/contest_a_\d+/, name)
  end

  test "check_in_interval returns 60 seconds" do
    assert_equal 60, Contest.check_in_interval
  end

  # --- Associations ---

  test "contest has users through contests_users" do
    contest = contests(:contest_a)
    assert_includes contest.users, users(:james)
  end

  # --- finish_open_vivas! (the contest page's "Finish open vivas" button) ---

  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  # contest_a with the viva fixture problem added (fixtures keep it out so the
  # contest-problem counts elsewhere stay put).
  def contest_with_viva
    contests(:contest_a).tap do |c|
      ContestProblem.create!(contest: c, problem: problems(:prob_viva), number: 3, enabled: true)
    end
  end

  # An open viva session: greeting, optional student answer, optional reply in flight.
  def open_viva(user:, answered:, in_flight: false, submitted_at: Time.zone.now)
    sub = Submission.create!(user: user, problem: problems(:prob_viva), language: viva_language,
                             status: :submitted, submitted_at: submitted_at)
    sub.viva_turns.create!(role: :assistant, status: :ok, content: 'hello')
    sub.viva_turns.create!(role: :student, status: :ok, content: 'my answer') if answered
    sub.viva_turns.create!(role: :assistant, status: :processing, content: nil) if in_flight
    sub
  end

  test "finish_open_vivas! sends an answered session to grading with a staff closing turn" do
    contest = contest_with_viva
    sub = open_viva(user: users(:james), answered: true)
    assert_enqueued_with(job: Llm::VivaGradeAssistJob) do
      assert_equal({graded: 1, archived: 0, skipped: 0}, contest.finish_open_vivas!)
    end
    sub.reload
    assert_predicate sub, :evaluating?
    assert sub.viva_turns.where(role: :system).where("content LIKE '%contest staff%grading begins%'").exists?,
           "must leave the staff closing turn in the transcript"
  end

  test "finish_open_vivas! archives a greeting-only session without grading" do
    contest = contest_with_viva
    sub = open_viva(user: users(:james), answered: false)
    assert_no_enqueued_jobs(only: Llm::VivaGradeAssistJob) do
      assert_equal({graded: 0, archived: 1, skipped: 0}, contest.finish_open_vivas!)
    end
    sub.reload
    assert_predicate sub, :submitted?
    assert sub.viva_archived_at.present?, "greeting-only session must be archived, not graded"
  end

  test "finish_open_vivas! skips a session whose assistant reply is still in flight" do
    contest = contest_with_viva
    sub = open_viva(user: users(:james), answered: true, in_flight: true)
    assert_no_enqueued_jobs(only: Llm::VivaGradeAssistJob) do
      assert_equal({graded: 0, archived: 0, skipped: 1}, contest.finish_open_vivas!)
    end
    sub.reload
    assert_predicate sub, :submitted?
    assert_nil sub.viva_archived_at
  end

  test "finish_open_vivas! leaves sessions started before the contest window alone" do
    contest = contest_with_viva
    sub = open_viva(user: users(:james), answered: true, submitted_at: contest.start - 1.hour)
    assert_equal({graded: 0, archived: 0, skipped: 0}, contest.finish_open_vivas!)
    assert_predicate sub.reload, :submitted?
  end

  test "finish_open_vivas! honours a user's extra time" do
    contest = contest_with_viva
    contest.contests_users.find_by!(user: users(:james)).update!(extra_time_second: 7200)
    open_viva(user: users(:james), answered: true, submitted_at: contest.stop + 1.hour)
    assert_equal({graded: 1, archived: 0, skipped: 0}, contest.finish_open_vivas!)
  end

  test "finish_open_vivas! ignores sessions of users not enrolled in the contest" do
    contest = contest_with_viva
    sub = open_viva(user: users(:john), answered: true) # john is not in contest_a
    assert_equal({graded: 0, archived: 0, skipped: 0}, contest.finish_open_vivas!)
    assert_predicate sub.reload, :submitted?
  end

  test "finish_open_vivas! ignores viva problems that are not in the contest" do
    contest_with_viva # prob_viva is in contest_a only
    sub = open_viva(user: users(:jack), answered: true) # jack is in contest_a AND contest_b
    assert_equal({graded: 0, archived: 0, skipped: 0}, contests(:contest_b).finish_open_vivas!)
    assert_predicate sub.reload, :submitted?
  end

  test "finish_open_vivas! is idempotent — a second click finds nothing" do
    contest = contest_with_viva
    open_viva(user: users(:james), answered: true)
    open_viva(user: users(:jack), answered: false)
    assert_equal({graded: 1, archived: 1, skipped: 0}, contest.finish_open_vivas!)
    assert_equal({graded: 0, archived: 0, skipped: 0}, contest.finish_open_vivas!)
  end

  # --- viva_grading_counts (the status line next to "Finish open vivas") ---

  def viva_session(user:, status:, archived: false, submitted_at: Time.zone.now)
    Submission.create!(user: user, problem: problems(:prob_viva), language: viva_language, status: status,
                       submitted_at: submitted_at, viva_archived_at: (archived ? Time.zone.now : nil))
  end

  test "viva_grading_counts counts in-window evaluating and grader_error sessions of enrolled users" do
    contest = contest_with_viva
    viva_session(user: users(:james), status: :evaluating)
    viva_session(user: users(:jack),  status: :evaluating)
    viva_session(user: users(:james), status: :grader_error)
    viva_session(user: users(:james), status: :done)                               # graded: not counted
    viva_session(user: users(:james), status: :submitted)                          # still open: not counted
    viva_session(user: users(:jack),  status: :evaluating, archived: true)         # archived: not counted
    viva_session(user: users(:john),  status: :evaluating)                         # not enrolled
    viva_session(user: users(:jack),  status: :evaluating, submitted_at: 2.days.ago) # outside the window
    assert_equal({grading: 2, errors: 1}, contest.viva_grading_counts)
  end

  test "viva_grading_counts is zero when nothing is waiting" do
    assert_equal({grading: 0, errors: 0}, contest_with_viva.viva_grading_counts)
  end

  # --- Problem order ---

  def numbers_of(contest)
    contest.problems_in_display_order.map { |cp| [cp.problem.name, cp.number] }
  end

  def contest_c_with(problems, numbers)
    c = contests(:contest_c)
    problems.each_with_index { |p, i| c.contests_problems.create!(problem: p, number: numbers[i]) }
    c.reload
  end

  def five_problems
    %i[prob_add prob_sub easy hard prob_viva].map { |n| problems(n) }
  end

  test "add_problems_and_assign_number continues after the highest number" do
    c = contests(:contest_a)
    c.add_problems_and_assign_number([problems(:hard)])
    c.save!
    assert_equal 3, c.contests_problems.find_by(problem: problems(:hard)).number
  end

  test "move_problem heals duplicates and moves one row" do
    ps = five_problems
    c = contest_c_with(ps, [1, 1, 2, 3, 4])
    assert_equal 4, c.move_problem(ps[4], :up)
    order = c.problems_in_display_order
    assert_equal ps[4].id, order[3].problem_id
    assert_equal [1, 2, 3, 4, 5], order.map(&:number)
  end

  test "move_problem with blank numbers moves one row" do
    ps = five_problems.first(4)
    c = contest_c_with(ps, [nil, nil, nil, nil])
    assert_equal 3, c.move_problem(ps[3], :up)
    order = c.problems_in_display_order
    assert_equal [1, 2, 3, 4], order.map(&:number)
    assert_equal ps[2].id, order.last.problem_id
  end

  test "move_problem down from the top does not duplicate" do
    ps = five_problems.first(4)
    c = contest_c_with(ps, [1, 2, 3, 4])
    c.move_problem(ps[0], :down)
    order = c.problems_in_display_order
    assert_equal [ps[1], ps[0], ps[2], ps[3]].map(&:id), order.map(&:problem_id)
    assert_equal [1, 2, 3, 4], order.map(&:number)
  end

  test "move_problem at the edge is a no-op" do
    ps = five_problems.first(4)
    c = contest_c_with(ps, [1, 2, 3, 4])
    assert_equal 1, c.move_problem(ps[0], :up)
    assert_equal ps.map(&:id), c.problems_in_display_order.map(&:problem_id)
    assert_equal 4, c.move_problem(ps[3], :down)
    assert_equal ps.map(&:id), c.problems_in_display_order.map(&:problem_id)
    assert_equal [1, 2, 3, 4], c.problems_in_display_order.map(&:number)
  end

  test "move_problem returns nil for a problem not in the contest" do
    c = contests(:contest_a)
    assert_nil c.move_problem(problems(:hard), :up)
  end

  test "reorder_problems! tolerates foreign, duplicate and missing ids" do
    a, b, cc, other = problems(:prob_add), problems(:prob_sub), problems(:easy), problems(:hard)
    c = contest_c_with([a, b, cc], [1, 2, 3])
    result = c.reorder_problems!([cc.id.to_s, other.id, cc.id, a.id])
    assert_equal [cc.id, a.id, b.id], result
    order = c.problems_in_display_order
    assert_equal [cc.id, a.id, b.id], order.map(&:problem_id)
    assert_equal [1, 2, 3], order.map(&:number)
  end

  test "ticking without a Stop time is refused" do
    c = contests(:contest_a)
    c.stop = nil
    c.outside_login_off = true
    assert_not c.valid?
    assert_includes c.errors[:outside_login_off], 'needs a Stop time'
  end
end
