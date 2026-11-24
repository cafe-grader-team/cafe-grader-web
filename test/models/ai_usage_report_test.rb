require "test_helper"

class AiUsageReportTest < ActiveSupport::TestCase
  setup do
    @contest = contests(:contest_a)              # start 1h ago, stop 3h from now; problems prob_add, easy
    @user    = users(:james)                     # james_in_contest_a (enabled)
    @answered = submissions(:add1_by_james)      # james on prob_add (in contest_a)
    @answered.update_columns(submitted_at: 30.minutes.ago, status: Submission.statuses[:submitted])
    @answered.viva_turns.create!(role: :system,    status: :ok, sequence: 0, content: "(interview start)")
    @answered.viva_turns.create!(role: :assistant, status: :ok, sequence: 1, content: "Q1?",
                                 created_at: 30.minutes.ago, updated_at: 30.minutes.ago + 8.seconds,
                                 llm_started_at: 30.minutes.ago + 3.seconds, llm_latency_ms: 5000, cost: 0.01)
    @answered.viva_turns.create!(role: :student,   status: :ok, sequence: 2, content: "A1")
    @answered.comments.create!(user: @user, kind: :llm_assist, status: :ok, title: "Assistance",
                               body: "hint", cost: 10, llm_cost: 0.02, llm_model: "claude-opus-4-5",
                               created_at: 20.minutes.ago, updated_at: 20.minutes.ago + 30.seconds,
                               llm_started_at: 20.minutes.ago + 25.seconds, llm_latency_ms: 5000,
                               prompt_tokens: 100, completion_tokens: 50)
    @report = AiUsageReport.new(@contest)
  end

  test "summary counts sessions, turns and assists" do
    s = @report.summary
    assert_equal 1, s[:sessions_opened]
    assert_equal 1, s[:answered]
    assert_equal 1, s[:turns]
    assert_equal 1, s[:assists]
    assert_in_delta 0.02, s[:assist_dollars], 0.0001
    assert_equal 10.0, s[:assist_points]
  end

  test "summary sums tokens in and out for viva turns and assists" do
    @answered.viva_turns.find_by(sequence: 1).update_columns(token_count_in: 1200, token_count_out: 80)
    s = AiUsageReport.new(@contest).summary
    assert_equal 1200, s[:turn_tokens_in]
    assert_equal 80,   s[:turn_tokens_out]
    assert_equal 100,  s[:assist_tokens_in]
    assert_equal 50,   s[:assist_tokens_out]
  end

  test "total cost adds viva turns, viva grading and priced assists" do
    VivaGrade.create!(submission: @answered, total_points: 70, cost: 0.05, llm_model: "m",
                      graded_at: 10.minutes.ago, created_at: 10.minutes.ago)
    s = AiUsageReport.new(@contest).summary
    assert_in_delta 0.01, s[:turn_cost], 0.0001
    assert_in_delta 0.05, s[:grade_cost], 0.0001
    assert_in_delta 0.08, s[:total_cost], 0.0001
  end

  test "distribution separates the kinds and computes total wait" do
    d = @report.distribution.index_by { |r| r[:kind] }
    assert_equal 8.0, d["viva turn"][:p95]   # updated - created = 8s
    assert_equal 30.0, d["assist"][:p95]
  end

  test "calls_json splits queued from model time" do
    turn = @report.calls_json.find { |c| c[:kind] == "viva turn" }
    assert_equal 3.0, turn[:queued_s]        # started - created
    assert_equal 5.0, turn[:model_s]         # latency_ms
    assert_equal 8.0, turn[:total_s]
  end

  test "a session with no student answer is counted as never answered" do
    silent = submissions(:sub1_by_james)       # james on prob_sub — NOT in contest_a
    # move it onto a contest problem so it is in scope
    silent.update_columns(problem_id: problems(:easy).id, submitted_at: 10.minutes.ago,
                          status: Submission.statuses[:submitted])
    silent.viva_turns.create!(role: :assistant, status: :ok, sequence: 1, content: "Q?",
                              created_at: 10.minutes.ago, updated_at: 10.minutes.ago + 120.seconds)
    report = AiUsageReport.new(@contest)
    assert_equal 1, report.never_answered.size
    assert_equal @user.login, report.never_answered.first[:login]
  end

  test "only enrolled users' calls are counted" do
    # john is not in contest_a; a viva turn on a contest problem by john must not appear
    outsider = submissions(:add1_by_john)      # john on prob_add (in contest_a); john not enrolled
    outsider.update_columns(submitted_at: 15.minutes.ago, status: Submission.statuses[:submitted])
    outsider.viva_turns.create!(role: :assistant, status: :ok, sequence: 1, content: "Q?",
                                created_at: 15.minutes.ago, updated_at: 15.minutes.ago + 4.seconds)
    assert_equal 1, AiUsageReport.new(@contest).summary[:turns], "outsider turn must be excluded"
  end

  test "grade calls count every run, superseded ones included, and flag failed runs" do
    @answered.viva_grades.create!(total_points: 40, graded_at: 15.minutes.ago, llm_model: 'g', cost: 0.03, llm_latency_ms: 7000,
                                  superseded_at: 10.minutes.ago, superseded_reason: 'replaced')
    @answered.viva_grades.create!(total_points: 60, graded_at: 10.minutes.ago, llm_model: 'g', cost: 0.04, llm_latency_ms: 8000)
    @answered.viva_grades.create!(graded_at: 5.minutes.ago, llm_model: 'g', cost: 0.01, superseded_at: 5.minutes.ago,
                                  superseded_reason: 'error', error: 'x')
    grades = @report.calls_json.select { |c| c[:kind] == "viva grade" }
    assert_equal 3, grades.size
    assert_equal %w[error ok ok], grades.map { |c| c[:status] }.sort
    assert_in_delta 0.08, grades.sum { |c| c[:cost].to_f }, 0.0001
  end

  test "a grade that ran after the window still counts; a session started outside the window does not" do
    @answered.viva_grades.create!(total_points: 60, graded_at: @report.window.end + 1.hour, llm_model: 'g', cost: 0.04)
    early = submissions(:sub1_by_james)
    early.update_columns(problem_id: problems(:easy).id, submitted_at: @contest.start - 1.day,
                         status: Submission.statuses[:done])
    early.viva_grades.create!(total_points: 50, graded_at: 10.minutes.ago, llm_model: 'g', cost: 0.02)
    s = AiUsageReport.new(@contest).summary
    assert_equal 1, s[:grades], "the late grade counts, the grade of the pre-window session does not"
    assert_equal 1, s[:grades_after_window]
    assert_in_delta 0.04, s[:grade_cost], 0.0001
    grade_bars = AiUsageReport.new(@contest).counts_chart[:datasets].find { |d| d[:label] == "viva grade" }[:data]
    assert_equal 0, grade_bars.sum, "the per-5-minute chart stays inside the window"
  end

  test "viva turns and assists carry their status" do
    @answered.viva_turns.create!(role: :assistant, status: :error, sequence: 3, content: "",
                                 created_at: 25.minutes.ago, updated_at: 25.minutes.ago + 2.seconds)
    rows = @report.calls_json
    assert_equal %w[error ok], rows.select { |c| c[:kind] == "viva turn" }.map { |c| c[:status] }.sort
    assert_equal %w[ok], rows.select { |c| c[:kind] == "assist" }.map { |c| c[:status] }
  end

  test "AI time is reported beside the wait" do
    d = @report.distribution.index_by { |r| r[:kind] }
    assert_equal 5.0, d["viva turn"][:ai_p95]
    assert_equal 5.0, d["assist"][:ai_mean]
    assert_nil d["viva grade"][:ai_mean]
    m = @report.by_model.find { |r| r[:model] == "claude-opus-4-5" }
    assert_equal 30.0, m[:p95]                 # wait
    assert_equal 5.0, m[:ai_p95]               # AI time
  end
end
