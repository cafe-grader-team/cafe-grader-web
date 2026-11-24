require "test_helper"

# The contest scope of the filter-driven reports (?contest=ID on Best Score /
# Submissions / User Activity): the contest's students, its problems and each
# student's own window replace the three filter cards. Plus the Submission
# report's Users card, which the contest scope made load-bearing again.
class ReportContestScopeTest < ActionDispatch::IntegrationTest
  setup do
    @contest = contests(:contest_a)      # start 1h ago, stop 3h from now; prob_add (#1), easy (#2)
    @james   = users(:james)             # student of contest_a, in group_a
    @jack    = users(:jack)              # student of contest_a, in no group
    @john    = users(:john)              # in group_a, NOT in contest_a
    @add     = problems(:prob_add)
    @easy    = problems(:easy)
  end

  # A submission row outside the model's submit checks (the fixtures' problem /
  # language rules are not the point here), like the viva tests do.
  def seed_sub(user, problem, at, points: 0)
    s = submissions(:add1_by_james).dup
    s.assign_attributes(user: user, problem: problem, submitted_at: at, points: points, number: nil)
    s.save!(validate: false)
    s
  end

  def query_ids(path, extra = {})
    post path, params: {contest: @contest.id}.merge(extra), as: :json
    assert_response :success
    response.parsed_body["data"].map { |r| r["id"] }
  end

  # --- the page ---

  test "a picked contest shows its scope and hides the filter cards" do
    sign_in_as("admin", "admin")
    get max_score_report_path(contest: @contest.id)
    assert_response :success
    # 3 students: jack, james and the disabled member — the rows Watch lists
    assert_select "#report-contest-scope", text: /contest_a.*2 problems.*3 students/m
    assert_select "select#report-contest option[selected][value=?]", @contest.id.to_s
    assert_select "form#max-score-filter-form .row.d-none", 1, "the three cards are hidden, not removed"
    assert_select "form#max-score-filter-form input[name=contest][value=?]", @contest.id.to_s
    assert_select "a[href=?]", max_score_report_path, text: /Clear contest/
    # the table renders with the contest's columns at once
    assert_select "[data-datatables--init-score-table-problem-ids-value=?]", [@add.id, @easy.id].to_s
    assert_select "[data-datatables--init-score-table-ajax-url-value=?]", max_score_query_report_path(contest: @contest.id)
  end

  test "contest-scoped Submissions and User Activity link students to their stat for this contest" do
    sign_in_as("admin", "admin")
    contest_stat = stat_contest_user_admin_path(-1234, @contest)
    [submission_report_path(contest: @contest.id), activity_report_path(contest: @contest.id)].each do |path|
      get path
      assert_response :success
      assert_includes response.body, %(user_path = "#{contest_stat}"), path
    end
    get submission_report_path
    assert_includes response.body, %(user_path = "#{stat_user_admin_path(-1234)}")
  end

  test "without a contest the page is unchanged and the picker offers the manageable contests" do
    sign_in_as("mary", "mary")           # editor of contest_a only
    get submission_report_path
    assert_response :success
    assert_select "#report-contest-scope", 0
    assert_select "form#filter_form .row.d-none", 0
    assert_select "select#report-contest option[value=?]", @contest.id.to_s
    assert_select "select#report-contest option[value=?]", contests(:contest_b).id.to_s, 0
  end

  test "a contest the viewer cannot manage is ignored and the page says so" do
    sign_in_as("mary", "mary")
    get activity_report_path(contest: contests(:contest_b).id)
    assert_response :success
    assert_match "not one you can manage", response.body
    assert_select "#report-contest-scope", 0
    assert_select "form#filter_form .row.d-none", 0
  end

  test "a reporter who manages no contest gets no picker" do
    sign_in_as("reba", "reba")           # reporter of group_a, no contest role
    get max_score_report_path
    assert_response :success
    assert_select "select#report-contest", 0
  end

  # --- the scope ---

  test "the Submission report uses each student's own window and the contest's students and problems" do
    sign_in_as("admin", "admin")
    ContestUser.where(contest: @contest, user: @james).update_all(start_offset_second: 1800, extra_time_second: 3600)
    inside  = [seed_sub(@james, @add, @contest.start + 10.minutes),
               seed_sub(@james, @easy, @contest.start - 10.minutes),      # james: 30 min head start
               seed_sub(@james, @add, @contest.stop + 30.minutes),        # james: 1 h extra time
               seed_sub(@jack, @add, @contest.start + 10.minutes)]
    outside = [seed_sub(@james, @add, @contest.stop + 2.hours),           # past james's extra time
               seed_sub(@jack, @add, @contest.start - 10.minutes),        # jack has no head start
               seed_sub(@jack, @add, @contest.stop + 30.minutes),         # jack has no extra time
               seed_sub(@john, @add, @contest.start + 10.minutes),        # not in the contest
               seed_sub(@james, problems(:prob_sub), @contest.start + 10.minutes)]  # not a contest problem

    ids = query_ids(submission_query_report_path(format: :json))
    assert_equal inside.map(&:id).sort, ids.sort
    assert_empty ids & outside.map(&:id)
  end

  test "the Activity report counts the same rows and lists students who never submitted" do
    sign_in_as("admin", "admin")
    seed_sub(@james, @add, @contest.start + 10.minutes, points: 100)
    seed_sub(@james, @easy, @contest.start + 20.minutes)
    seed_sub(@jack, @add, @contest.stop + 30.minutes)                     # outside jack's window

    post activity_query_report_path(format: :json), params: {contest: @contest.id, show_inactive: "true"}, as: :json
    assert_response :success
    rows = response.parsed_body["data"].index_by { |r| r["login"] }
    assert_equal 2, rows["james"]["sub_count"]
    assert_equal 1, rows["james"]["solved_count"]
    assert_equal 0, rows["jack"]["sub_count"], "jack's only submission is outside his window"
    assert_nil rows["mary"], "editors are not students"
    assert_nil rows["john"], "not in the contest"
  end

  test "Best Score with a contest gives the Watch page's numbers, with seat and remark" do
    sign_in_as("admin", "admin")
    ContestUser.where(contest: @contest, user: @james).update_all(seat: "A1", remark: "late start")
    seed_sub(@james, @add, @contest.start + 5.minutes, points: 40)
    seed_sub(@james, @add, @contest.start + 15.minutes, points: 100)
    seed_sub(@james, @easy, @contest.start + 25.minutes, points: 60)
    seed_sub(@jack, @add, @contest.start + 30.minutes, points: 70)
    seed_sub(@jack, @add, @contest.stop + 1.hour, points: 100)            # outside the window

    post max_score_query_report_path(format: :json), params: {contest: @contest.id}, as: :json
    assert_response :success
    body = response.parsed_body

    watch = JSON.parse(@contest.score_report.to_json)["score"]
    %w[james jack disabled].each do |login|
      assert_equal watch[login], body["result"]["score"][login], "#{login}'s row must match the Watch page"
    end
    assert_equal "100.0", body["result"]["score"]["james"]["final_score_#{@add.id}"].to_s
    assert_equal "70.0",  body["result"]["score"]["jack"]["final_score_#{@add.id}"].to_s

    rows = body["data"].index_by { |r| r["login"] }
    assert_equal %w[disabled jack james], rows.keys.sort, "the rows Watch lists: students, editors left out"
    assert_equal "A1", rows["james"]["seat"]
    assert_equal "late start", rows["james"]["remark"]
    assert_equal @james.id, rows["james"]["user_id"]
    assert_equal [@add.id, @easy.id], body["problem"].map { |p| p["id"] }, "contest order"
  end

  test "a contest editor still sees only the problems they may report on" do
    set_grader_config("system.use_problem_group", true)   # off in the fixtures: then no editor reports on anything
    sign_in_as("mary", "mary")           # editor of group_a (prob_add, prob_sub); easy is in no group of hers
    get max_score_report_path(contest: @contest.id)
    assert_response :success
    assert_select "[data-datatables--init-score-table-problem-ids-value=?]", [@add.id].to_s
  ensure
    set_grader_config("system.use_problem_group", false)
  end

  # --- the Users card on the Submission report (ignored 2024-09-30 .. rev 2209) ---

  test "the Submission report respects the Users card" do
    sign_in_as("admin", "admin")
    # fixtures are all submitted 2019-10-22; admin is an editor of group_a, john and james its users
    range = {use: "time", from_time: "2019-01-01 00:00", to_time: "2020-12-31 00:00"}
    post submission_query_report_path(format: :json), as: :json,
         params: {sub_range: range, probs: {use: "all"},
                  users: {use: "group", group_ids: [groups(:group_a).id], only_users: "1"}}
    assert_response :success
    logins = response.parsed_body["data"].map { |r| r["login"] }.uniq.sort
    assert_equal %w[james john], logins, "the editor's own submissions must be filtered out"
  end

  # --- entry points ---

  test "the contest page links the three reports with the contest picked" do
    sign_in_as("admin", "admin")
    get contest_path(@contest)
    assert_response :success
    assert_select "a.dropdown-item[href=?]", max_score_report_path(contest: @contest.id)
    assert_select "a.dropdown-item[href=?]", submission_report_path(contest: @contest.id)
    assert_select "a.dropdown-item[href=?]", activity_report_path(contest: @contest.id)
  end

  test "the AI report points at the contest AI Usage page instead of a picker" do
    sign_in_as("admin", "admin")
    get ai_report_path
    assert_response :success
    assert_match "AI Usage page", response.body
    assert_select "select#report-contest", 0
  end

  # --- deduction cap (spec 2026-11-21) ---

  def charge_ai(sub, cost)
    sub.comments.create!(user: sub.user, kind: 'llm_assist', status: 'ok', cost: cost, title: 't', body: 'b')
  end

  test "Best Score with a contest uses the contest's deduction cap, never a deduction_cap param" do
    sign_in_as("admin", "admin")
    @contest.update!(deduction_cap: 30)
    charge_ai(seed_sub(@james, @add, @contest.start + 5.minutes, points: 90), 45)
    post max_score_query_report_path(format: :json), params: {contest: @contest.id, deduction_cap: 0}, as: :json
    row = response.parsed_body["result"]["score"]["james"]
    assert_equal 70.0, row["final_score_#{@add.id}"].to_f
    assert_equal JSON.parse(@contest.score_report.to_json)["score"]["james"], row
  end

  test "global Best Score applies its deduction_cap param and ignores contests' caps" do
    sign_in_as("admin", "admin")
    @contest.update!(deduction_cap: 10)
    charge_ai(seed_sub(@james, @add, 10.minutes.ago, points: 90), 45)
    query = {probs: {use: 'ids', ids: [@add.id]}, users: {use: 'enabled'}}

    post max_score_query_report_path(format: :json), params: query, as: :json
    assert_equal 55.0, response.parsed_body["result"]["score"]["james"]["final_score_#{@add.id}"].to_f

    post max_score_query_report_path(format: :json), params: query.merge(deduction_cap: 30), as: :json
    row = response.parsed_body["result"]["score"]["james"]
    assert_equal 70.0, row["final_score_#{@add.id}"].to_f
    assert_equal 30.0, row["total_cost_#{@add.id}"].to_f

    post max_score_query_report_path(format: :json), params: query.merge(deduction_cap: 'abc'), as: :json
    assert_equal 55.0, response.parsed_body["result"]["score"]["james"]["final_score_#{@add.id}"].to_f
  end

  test "the global Best Score page has a deduction cap box that reaches the table's data URL" do
    sign_in_as("admin", "admin")
    get max_score_report_path
    assert_select "input[name=deduction_cap]", 1

    post max_score_table_report_path, params: {deduction_cap: "30"}, as: :turbo_stream
    assert_match "deduction_cap=30", response.body
    post max_score_table_report_path, params: {deduction_cap: "abc"}, as: :turbo_stream
    assert_no_match "deduction_cap=", response.body
  end

  test "a contest-scoped Best Score has no cap box and names the contest's cap" do
    sign_in_as("admin", "admin")
    get max_score_report_path(contest: @contest.id)
    assert_select "input[name=deduction_cap]", 0
    assert_select "#report-contest-scope", text: /no deduction cap/

    @contest.update!(deduction_cap: 30)
    get max_score_report_path(contest: @contest.id)
    assert_select "#report-contest-scope", text: /deduction cap 30/
  end

  test "only Best Score's scope card mentions the deduction cap" do
    sign_in_as("admin", "admin")
    @contest.update!(deduction_cap: 30)
    get activity_report_path(contest: @contest.id)
    assert_select "#report-contest-scope", 1
    assert_no_match "deduction cap", response.body
    get submission_report_path(contest: @contest.id)
    assert_no_match "deduction cap", response.body
  end
end
