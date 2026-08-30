require 'test_helper'

class SubmissionRepairReportTest < ActiveSupport::TestCase
  setup do
    @original = submissions(:add1_by_john)
    @original.update_columns(status: Submission.statuses[:done], points: 20)
    @shadow = Submission.new(user: @original.user, problem: @original.problem,
                             language: @original.language, submitted_at: Time.zone.now,
                             source: 's', repaired_from_id: @original.id)
    @shadow.save!(validate: false)
    @shadow.update_columns(points: 90, status: Submission.statuses[:done])

    SubmissionRepair.create!(original_submission: @original, repaired_submission: @shadow,
                             status: :accepted, budget_lines: 2, budget_chars: 20,
                             fix_category: 'io_format', changed_chars: 3, rounds_used: 2,
                             rounds_log: [{'round' => 1, 'gate' => 'over_budget', 'changed_lines' => 5, 'changed_chars' => 60},
                                          {'round' => 2, 'gate' => 'accepted', 'changed_lines' => 1, 'changed_chars' => 3}],
                             token_count_in: 200, token_count_out: 80, cost: 0.0, run_label: 'runA')
    other = submissions(:sub1_by_james)
    other.update_columns(status: Submission.statuses[:done], points: 0)
    SubmissionRepair.create!(original_submission: other, status: :over_budget,
                             budget_lines: 2, budget_chars: 20, changed_chars: 99,
                             rounds_used: 3, run_label: 'runA')
  end

  test "report_for aggregates rescue rate, gap, categories, compliance" do
    report = SubmissionRepair.report_for(['runA'])
    add_stats = report['runA'][@original.problem.name]
    assert_equal 1, add_stats[:targets]
    assert_equal 1, add_stats[:rescued]
    assert_equal 1.0, add_stats[:rescue_rate]
    assert_equal 70.0, add_stats[:mean_gap]      # 90 - 20
    assert_equal 70.0, add_stats[:median_gap]    # single element (odd N) -> the element itself
    assert_equal({'io_format' => 1}, add_stats[:categories])
    assert_equal({within: 0, total: 1}, add_stats[:compliance][1])
    assert_equal({within: 1, total: 1}, add_stats[:compliance][2])
    assert_equal 200, add_stats[:tokens_in]
    assert_equal 0, add_stats[:ungradeable]

    sub_stats = report['runA'][submissions(:sub1_by_james).problem.name]
    assert_equal 0, sub_stats[:rescued]
    assert_equal({'over_budget' => 1}, sub_stats[:statuses])
  end

  test "report_for separates run labels" do
    SubmissionRepair.create!(original_submission: @original, status: :no_change,
                             budget_lines: 2, budget_chars: 20, run_label: 'runB')
    report = SubmissionRepair.report_for(%w[runA runB])
    assert_equal 2, report.keys.size
    assert_equal({'no_change' => 1}, report['runB'][@original.problem.name][:statuses])
  end

  test "report_for computes the true median (average of the middle two) for an even-sized gap sample" do
    second_original = submissions(:add1_by_james)
    second_original.update_columns(status: Submission.statuses[:done], points: 25)
    second_shadow = Submission.new(user: second_original.user, problem: second_original.problem,
                                   language: second_original.language, submitted_at: Time.zone.now,
                                   source: 's2', repaired_from_id: second_original.id)
    second_shadow.save!(validate: false)
    second_shadow.update_columns(points: 40, status: Submission.statuses[:done])

    # Two accepted+graded repairs on the same problem (prob_add) -> gaps [70, 15],
    # an even-sized (N=2) sample. True median = (15 + 70) / 2.0 = 42.5, not the
    # upper-middle element (70) that `sorted[size / 2]` would incorrectly pick.
    SubmissionRepair.create!(original_submission: @original, repaired_submission: @shadow,
                             status: :accepted, budget_lines: 2, budget_chars: 20, run_label: 'runC')
    SubmissionRepair.create!(original_submission: second_original, repaired_submission: second_shadow,
                             status: :accepted, budget_lines: 2, budget_chars: 20, run_label: 'runC')

    report = SubmissionRepair.report_for(['runC'])
    stats = report['runC'][@original.problem.name]
    assert_equal 42.5, stats[:median_gap]
  end

  test "report_for counts non-terminal shadows as ungradeable, never as 0-point grades" do
    # The void a68_final grading pass: every shadow grader_error'd (judge
    # 404s on missing testcase blobs) and the report read the error-zeros as
    # "0 rescues / 63 negative gaps". Gap stats must only see real outcomes.
    original = submissions(:add1_by_james)
    original.update_columns(status: Submission.statuses[:done], points: 60)
    err_shadow = Submission.new(user: original.user, problem: original.problem,
                                language: original.language, submitted_at: Time.zone.now,
                                source: 'e', repaired_from_id: original.id)
    err_shadow.save!(validate: false)
    err_shadow.update_columns(points: 0, status: Submission.statuses[:grader_error])
    SubmissionRepair.create!(original_submission: original, repaired_submission: err_shadow,
                             status: :accepted, budget_lines: 2, budget_chars: 20, run_label: 'runE')

    inflight = Submission.new(user: @original.user, problem: @original.problem,
                              language: @original.language, submitted_at: Time.zone.now,
                              source: 'f', repaired_from_id: @original.id)
    inflight.save!(validate: false)
    inflight.update_columns(points: 0, status: Submission.statuses[:evaluating])
    SubmissionRepair.create!(original_submission: @original, repaired_submission: inflight,
                             status: :accepted, budget_lines: 2, budget_chars: 20, run_label: 'runE')

    stats = SubmissionRepair.report_for(['runE'])['runE'][original.problem.name]
    assert_equal 2, stats[:ungradeable]
    assert_equal 0, stats[:rescued]
    assert_nil stats[:mean_gap], 'error/in-flight shadows must not enter the gap sample as 0-point grades'
    assert_nil stats[:median_gap]
  end

  test "a compilation_error shadow is a real grade (damage), not ungradeable" do
    original = submissions(:add1_by_james)
    original.update_columns(status: Submission.statuses[:done], points: 60)
    broken = Submission.new(user: original.user, problem: original.problem,
                            language: original.language, submitted_at: Time.zone.now,
                            source: 'b', repaired_from_id: original.id)
    broken.save!(validate: false)
    broken.update_columns(points: 0, status: Submission.statuses[:compilation_error])
    SubmissionRepair.create!(original_submission: original, repaired_submission: broken,
                             status: :accepted, budget_lines: 2, budget_chars: 20, run_label: 'runF')

    stats = SubmissionRepair.report_for(['runF'])['runF'][original.problem.name]
    assert_equal 0, stats[:ungradeable]
    assert_equal(-60.0, stats[:mean_gap], 'the repair broke the build — that IS a real negative gap')
  end

  test "median returns nil for empty, the element for odd N, and the averaged pair for even N" do
    assert_nil SubmissionRepair.median([])
    assert_equal 5, SubmissionRepair.median([1, 5, 9])
    assert_equal 25.0, SubmissionRepair.median([10, 20, 30, 40])
  end
end
