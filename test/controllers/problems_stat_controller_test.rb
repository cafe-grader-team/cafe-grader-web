require "test_helper"

# /problems/:id/stat — the per-problem statistics page.
class ProblemsStatControllerTest < ActionDispatch::IntegrationTest
  # Expected href of the toolbar "Score report" link (mirrors ProblemsHelper#problem_score_report_path).
  def report_link(prob, group = nil)
    query = { probs: { use: "ids", ids: [prob.id] } }
    query[:users] = { use: "group", group_ids: group.id } if group
    max_score_report_path(query)
  end

  def assert_report_link(prob, group = nil)
    get stat_problem_path(prob)
    assert_response :success
    assert_select "a[href=?]", report_link(prob, group), text: /Score report/
  end

  test "stat page links to the Best Score report with the problem and its group pre-picked" do
    sign_in_as("admin", "admin")
    assert_report_link problems(:prob_add), groups(:group_a)   # prob_add is in group_a only
  end

  test "a problem in no group links to the report without a user-group prefill" do
    sign_in_as("admin", "admin")
    assert_report_link problems(:easy)
  end

  # Problem#report_group_for tiers: live group with submissions > any group
  # with submissions (archived included) > newest live group.
  test "pre-picked group: a live section with submissions beats a newer one without" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)   # 3 fixture submissions, all by group_a members
    newer = Group.create!(name: "NewSection", enabled: true)
    GroupProblem.create!(group: newer, problem: prob)
    assert_report_link prob, groups(:group_a)   # newer group has no submitters -> group_a (3 subs) wins

    %i[admin john james].each { |u| GroupUser.create!(group: newer, user: users(u), role: :user) }
    assert_report_link prob, newer              # 3 vs 3 -> tie -> newest wins
  end

  test "pre-picked group: a live section with submissions beats the archived cohort with more" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    groups(:group_a).update!(enabled: false)    # last year's cohort, 3 subs, archived
    current = Group.create!(name: "Current", enabled: true)
    GroupProblem.create!(group: current, problem: prob)
    GroupUser.create!(group: current, user: users(:john), role: :user)   # john's 1 sub now counts here too
    assert_report_link prob, current            # live + submissions (1) beats archived (3)
  end

  test "pre-picked group: with no live submissions, the archived cohort that used the problem wins" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    groups(:group_a).update!(enabled: false)    # the cohort with the data, archived
    Group.create!(name: "Current", enabled: true).then { |g| GroupProblem.create!(group: g, problem: prob) }
    assert_report_link prob, groups(:group_a)   # live group has no submitters -> archived cohort wins
  end

  test "pre-picked group: with no submissions anywhere, the newest live group wins" do
    sign_in_as("admin", "admin")
    prob = problems(:easy)                      # no submissions, no groups
    older = Group.create!(name: "SecA", enabled: true)
    newer = Group.create!(name: "SecB", enabled: true)
    [older, newer].each { |g| GroupProblem.create!(group: g, problem: prob) }
    assert_report_link prob, newer
  end

  test "a disabled group membership is not pre-picked" do
    sign_in_as("admin", "admin")
    groups_problems(:add_in_group_a).update!(enabled: false)
    assert_report_link problems(:prob_add)
  end

  # The stat page sits behind group_editor_authorization (ProblemsController),
  # so besides admins only group editors reach it — and every editor can report
  # on their own group's problems, hence the link is shown unconditionally.
  test "a group editor gets the link with their group pre-picked" do
    set_grader_config("system.use_problem_group", true)   # reports are group-scoped
    sign_in_as("mary", "mary")                             # editor of group_a; prob_add is in group_a
    assert_report_link problems(:prob_add), groups(:group_a)
  end
end
