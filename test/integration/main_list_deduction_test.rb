require "test_helper"

# The student problem list's "Full score reduced by" line under the deduction
# cap (spec docs/superpowers/specs/2026-11-21-deduction-cap-spending-limit-design.md):
# in contest mode the running contest's cap applies; running contests that
# disagree, and normal mode, show the raw reduction, with a notice when a
# contest of the student's sets a cap.
class MainListDeductionTest < ActionDispatch::IntegrationTest
  setup do
    @a    = contests(:contest_a)   # start 1h ago, stop 3h from now; prob_add, easy
    @b    = contests(:contest_b)   # start 2h ago, stop 2h from now; easy, hard
    @add  = problems(:prob_add)
    @easy = problems(:easy)
    @hard = problems(:hard)
    set_grader_config('system.mode', 'contest')
  end

  teardown { reset_grader_config_cache }

  def seed_sub(user, problem, at, points: 50)
    s = submissions(:add1_by_james).dup
    s.assign_attributes(user: user, problem: problem, submitted_at: at, points: points, number: nil)
    s.save!(validate: false)
    s
  end

  def charge_ai(sub, cost)
    sub.comments.create!(user: sub.user, kind: 'llm_assist', status: 'ok', cost: cost, title: 't', body: 'b')
  end

  def list_body(login)
    sign_in_as(login, "morning")
    get list_main_path
    assert_response :success
    response.body
  end

  test "one running contest: the cap lowers the reduction" do
    @a.update!(deduction_cap: 30)
    charge_ai(seed_sub(users(:james), @add, @a.start + 5.minutes), 45)
    assert_match "Full score reduced by 30 (capped; 45 before the cap)", list_body("james")
  end

  test "a cap that is not reached changes nothing" do
    @a.update!(deduction_cap: 30)
    charge_ai(seed_sub(users(:james), @add, @a.start + 5.minutes), 20)
    body = list_body("james")
    assert_match "Full score reduced by 20", body
    assert_no_match(/capped;|may cap this/, body)
  end

  test "two running contests: each problem uses its own contest's cap" do
    @a.update!(deduction_cap: 30)
    @b.update!(deduction_cap: 20)
    charge_ai(seed_sub(users(:jack), @add, @a.start + 5.minutes), 45)    # only in contest_a
    charge_ai(seed_sub(users(:jack), @hard, @b.start + 5.minutes), 45)   # only in contest_b
    body = list_body("jack")
    assert_match "Full score reduced by 30 (capped; 45 before the cap)", body
    assert_match "Full score reduced by 20 (capped; 45 before the cap)", body
  end

  test "a problem in two running contests with different caps shows the raw reduction and the notice" do
    @a.update!(deduction_cap: 30)
    @b.update!(deduction_cap: 20)
    charge_ai(seed_sub(users(:jack), @easy, @a.start + 5.minutes), 45)   # easy is in both
    assert_match "Full score reduced by 45 (contest grading may cap this)", list_body("jack")
  end

  test "in contest mode a hint counts only when revealed inside the contest window" do
    reveal = comments(:hint_for_add).comment_reveals.create!(user: users(:james))   # costs 1.5
    reveal.update_columns(created_at: @a.start - 1.day)
    assert_no_match "Full score reduced by", list_body("james")

    reveal.update_columns(created_at: @a.start + 5.minutes)
    get list_main_path
    assert_match "Full score reduced by 1.5", response.body
  end

  test "normal mode shows the raw reduction with a notice when a contest of the student's sets a cap" do
    set_grader_config('system.mode', 'standard')
    charge_ai(seed_sub(users(:james), @add, 2.days.ago), 45)
    body = list_body("james")
    assert_match "Full score reduced by 45", body
    assert_no_match "may cap this", body

    @a.update!(deduction_cap: 30)
    get list_main_path
    assert_match "Full score reduced by 45 (contest grading may cap this)", response.body
  end

  test "contest mode with no running contest renders without any reduction" do
    [@a, @b].each { |c| c.update_columns(start: 2.days.ago, stop: 1.day.ago) }
    @a.update!(deduction_cap: 30)
    charge_ai(seed_sub(users(:james), @add, 2.days.ago + 1.hour), 45)
    assert_no_match "Full score reduced by", list_body("james")
  end

  test "a contest where the student's membership is disabled does not set the cap" do
    @a.update!(deduction_cap: 30)
    @b.update!(deduction_cap: 20)
    contests_users(:jack_in_contest_a).update!(enabled: false)
    charge_ai(seed_sub(users(:jack), @easy, @b.start + 5.minutes), 45)   # easy is in both
    assert_match "Full score reduced by 20 (capped; 45 before the cap)", list_body("jack")
  end

  test "the hint confirm box in a running contest shows the cap and that nothing more counts" do
    @a.update!(deduction_cap: 30)
    charge_ai(seed_sub(users(:james), @add, @a.start + 5.minutes), 45)
    sign_in_as("james", "morning")
    get direct_edit_problem_submissions_path(problem_id: @add.id)
    assert_response :success
    # the box is markdown rendered to HTML, then JSON-encoded into data-turbo-confirm
    assert_match "contest_a", response.body
    assert_match "caps hint and AI deductions at 30 points per problem.", response.body
    assert_match "You have reached the cap, so this costs you nothing more.", response.body
  end
end
