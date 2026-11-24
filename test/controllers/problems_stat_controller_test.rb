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

  # --- summary, By-group card, and the AJAX-loaded submissions table ---

  test "a viva problem says test-drives are not counted, with their number" do
    prob = problems(:prob_viva)
    Submission.new(user: users(:admin), problem: prob, language: languages(:Language_cpp),
                   submitted_at: Time.zone.now, test_drive: true).save!(validate: false)
    sign_in_as("admin", "admin")
    get stat_problem_path(prob)
    assert_response :success
    assert_select "#test-drive-note", text: /test-drives are not counted.*\(1 test-drive so far\)/m
  end

  test "a code problem has no test-drive note" do
    sign_in_as("admin", "admin")
    get stat_problem_path(problems(:prob_add))
    assert_response :success
    assert_select "#test-drive-note", count: 0
  end

  test "summary is a distinct-user count with a percentage" do
    submissions(:add1_by_john).update_columns(points: 100)
    sign_in_as("admin", "admin")
    get stat_problem_path(problems(:prob_add))
    assert_response :success
    assert_match %r{1/3 \(33\.3%\)}, response.body    # admin, john, james attempted; john solved
  end

  test "By group card lists each reportable group with counts and a report link" do
    submissions(:add1_by_john).update_columns(points: 100)
    submissions(:add1_by_james).update_columns(points: 40)
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    get stat_problem_path(prob)
    assert_response :success
    assert_select "#by-group-card" do
      assert_select "tbody tr", count: 1
      assert_select "tbody tr a[href=?]", report_link(prob, groups(:group_a)), text: "GroupA"
      assert_select "tbody tr td", text: "2"      # members
      assert_select "tbody tr td", text: "1 / 2"  # solved / attempted
      assert_select "tbody tr td", text: "70.0"   # mean best
    end
  end

  # Archived cohorts stay linked to a problem forever, so the card would grow a
  # few rows every semester. Live groups stay visible; archived ones fold.
  def link_archived_cohort(prob)
    old = Group.create!(name: "Cohort2568", enabled: false)
    GroupProblem.create!(group: old, problem: prob)
    GroupUser.create!(group: old, user: users(:jack), role: :user)
    Submission.create!(user: users(:jack), problem: prob, language: languages(:Language_c),
                       source: "x", source_filename: "a.c", status: :done, submitted_at: Time.zone.now,
                       points: 100, number: 1)
    old
  end

  test "By group card shows live groups open and folds archived ones behind a toggle" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    link_archived_cohort(prob)
    get stat_problem_path(prob)
    assert_response :success
    assert_select "#by-group-card" do
      assert_select "tbody:not(.collapse) tr", count: 1              # GroupA, live
      assert_select "tbody:not(.collapse) tr a", text: "GroupA"
      assert_select "tbody#by-group-archived.collapse tr", count: 1  # Cohort2568, folded
      assert_select "tbody#by-group-archived tr a", text: "Cohort2568"
      assert_select "tbody#by-group-archived tr td", text: "1 / 1"
      assert_select "button[data-bs-toggle=collapse][data-bs-target='#by-group-archived']", text: /1 archived group\b/
    end
  end

  test "By group card shows archived groups open when no live group is linked" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    groups(:group_a).update!(enabled: false)
    get stat_problem_path(prob)
    assert_response :success
    assert_select "#by-group-card tbody:not(.collapse) tr a", text: "GroupA"
    assert_select "#by-group-card tbody:not(.collapse) tr .badge", text: "archived"
    assert_select "#by-group-archived", count: 0
  end

  test "By group card has no archived toggle when every linked group is live" do
    sign_in_as("admin", "admin")
    get stat_problem_path(problems(:prob_add))
    assert_response :success
    assert_select "#by-group-card tbody tr", count: 1
    assert_select "#by-group-archived", count: 0
    assert_select "#by-group-card button[data-bs-toggle=collapse]", count: 0
  end

  test "By group card is absent when the problem is in no group" do
    sign_in_as("admin", "admin")
    get stat_problem_path(problems(:easy))
    assert_response :success
    assert_select "#by-group-card", count: 0
  end

  test "submission rows are no longer rendered inline; the table loads them by AJAX" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    get stat_problem_path(prob)
    assert_response :success
    assert_select "#main_table tbody tr", count: 0
    assert_match stat_query_problem_path(prob), response.body
  end

  test "stat_query returns one JSON row per regular submission with the table's fields" do
    submissions(:add1_by_john).update_columns(points: 100, ip_address: "10.0.0.7", grader_comment: "PP")
    sign_in_as("admin", "admin")
    post stat_query_problem_path(problems(:prob_add))
    assert_response :success
    rows = JSON.parse(response.body)["data"]
    assert_equal 3, rows.size
    john = rows.find { |r| r["login"] == "john" }
    assert_equal submissions(:add1_by_john).id, john["id"]
    assert_equal users(:john).id, john["user_id"]
    assert_equal "john", john["full_name"]
    assert_equal "C", john["pretty_name"]
    assert_equal 100, john["points"]
    assert_equal "PP", john["grader_comment"]
    assert_equal "10.0.0.7", john["ip_address"]
    assert_match %r{2019-10-22}, john["submitted_at"]
  end

  test "stat_query is refused for a user who cannot report on the problem" do
    sign_in_as("jack", "jack")   # in no group
    post stat_query_problem_path(problems(:prob_add))
    assert_response :redirect
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

  # A problem nobody has submitted to divides 0 by 0 when computing the solved
  # percentage. Float 0.0/0 is NaN and NaN.round(1) returns NaN rather than
  # raising, so the bug is silent: the page renders the literal "NaN%".
  test "a problem with no submissions shows no NaN in the solved/attempted summary" do
    sign_in_as("admin", "admin")
    prob = problems(:easy)
    assert_empty Submission.where(problem: prob), "fixture precondition: :easy has no submissions"

    get stat_problem_path(prob)
    assert_response :success
    # Match "NaN%" specifically, not bare /NaN/ -- the layout's go-to-submission
    # widget legitimately calls isNaN() and would match a looser pattern.
    assert_no_match(/NaN%/, response.body, "solved/attempted summary must not render NaN%")
    assert_select ".card-body", text: /No submissions yet/
  end

  # The stat page sits behind group_editor_authorization (ProblemsController),
  # so besides admins only group editors reach it — and every editor can report
  # on their own group's problems, hence the link is shown unconditionally.
  test "a group editor gets the link with their group pre-picked" do
    set_grader_config("system.use_problem_group", true)   # reports are group-scoped
    sign_in_as("mary", "mary")                             # editor of group_a; prob_add is in group_a
    assert_report_link problems(:prob_add), groups(:group_a)
  end

  # --- AI assist card (right column) ---

  test "AI assist card lists requests on the problem's submissions by model; absent when there are none" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_add)
    get stat_problem_path(prob)
    assert_select "#llm-usage-card", count: 0

    Comment.create!(commentable: submissions(:add1_by_john), user: users(:john), kind: 'llm_assist', status: 'ok',
                    llm_model: 'gemini-x', cost: 10, llm_cost: 0.25, prompt_tokens: 1200, completion_tokens: 300, title: 't')
    Comment.create!(commentable: submissions(:add1_by_james), user: users(:james), kind: 'llm_assist', status: 'ok',
                    llm_model: 'gemini-x', cost: 10, title: 't')
    get stat_problem_path(prob)
    assert_select "#llm-usage-card tbody tr", count: 1
    assert_select "#llm-usage-card tbody tr td", text: "2"                          # requests
    assert_select "#llm-usage-card tbody tr td", text: "20"                         # points charged
    assert_select "#llm-usage-card tbody tr td", text: /\$0\.25 \(1 of 2 priced\)/  # one row unpriced
    assert_select "#llm-usage-card tbody tr td", text: "1.2k / 300"                 # tokens in / out
  end
end
