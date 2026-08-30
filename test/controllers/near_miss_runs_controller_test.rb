require 'test_helper'

class NearMissRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original = submissions(:add1_by_john)
    @original.update_columns(status: Submission.statuses[:done], points: 40,
                             grader_comment: 'PP--')
    @shadow = Submission.new(user: @original.user, problem: @original.problem,
                             language: @original.language, submitted_at: Time.zone.now,
                             source: "int main(){}", repaired_from_id: @original.id)
    @shadow.save!(validate: false)
    @shadow.update_columns(points: 100, status: Submission.statuses[:done],
                           grader_comment: 'PPPP')
    @repair = SubmissionRepair.create!(
      original_submission: @original, repaired_submission: @shadow,
      status: :accepted, budget_lines: 2, budget_chars: 20,
      changed_lines: 1, changed_chars: 18, rounds_used: 1,
      fix_category: 'syntax', llm_model: 'qwen3.5',
      token_count_in: 1200, token_count_out: 340, cost: 0.0,
      run_label: 'test-run-1', remark: 'added missing include',
      patch: "@1\n+#include <cstdint>",
      rounds_log: [{'round' => 1, 'changed_lines' => 1, 'changed_chars' => 18,
                    'gate' => 'accepted'}],
      llm_response: '{"choices":[]}')
    @failed = SubmissionRepair.create!(
      original_submission: @original, status: :failed,
      budget_lines: 2, budget_chars: 20, run_label: 'test-run-2',
      remark: 'transport exploded')
  end

  # --- authorization (admin-only; template: tags_controller_test) ---

  test "unauthenticated cannot browse runs" do
    get near_miss_runs_path
    assert_redirected_to login_main_path
    get near_miss_run_path(runs: 'test-run-1')
    assert_redirected_to login_main_path
    get near_miss_repair_path(@repair)
    assert_redirected_to login_main_path
  end

  test "normal user cannot browse runs" do
    sign_in_as('john', 'hello')
    get near_miss_runs_path
    assert_redirected_to list_main_path
  end

  test "group editor cannot browse runs" do
    sign_in_as('mary', 'mary')
    get near_miss_runs_path
    assert_redirected_to list_main_path
  end

  # --- index ---

  test "index lists runs with aggregates" do
    sign_in_as('admin', 'admin')
    get near_miss_runs_path
    assert_response :success
    assert_match 'test-run-1', response.body
    assert_match 'test-run-2', response.body
    assert_match 'qwen3.5', response.body
    assert_match '2L / 20C', response.body
  end

  # --- show ---

  test "show renders per-problem stats and attempts for one run" do
    sign_in_as('admin', 'admin')
    get near_miss_run_path(runs: 'test-run-1')
    assert_response :success
    assert_match @original.problem.name, response.body
    assert_match "##{@repair.id}", response.body
    # rescued: 40 -> 100 gap
    assert_match '+60', response.body
  end

  test "show renders multiple runs side by side" do
    sign_in_as('admin', 'admin')
    get near_miss_run_path(runs: 'test-run-1,test-run-2')
    assert_response :success
    assert_match 'test-run-1', response.body
    assert_match 'test-run-2', response.body
  end

  test "show accepts the checkbox array form" do
    sign_in_as('admin', 'admin')
    get near_miss_run_path(runs: ['test-run-1', 'test-run-2'])
    assert_response :success
    assert_match 'test-run-2', response.body
  end

  test "show filters attempts by status" do
    sign_in_as('admin', 'admin')
    get near_miss_run_path(runs: 'test-run-1,test-run-2', status: 'failed')
    assert_response :success
    assert_match near_miss_repair_path(@failed), response.body
    assert_no_match Regexp.new(Regexp.escape("#{near_miss_repair_path(@repair)}\"")), response.body
  end

  test "show with unknown label renders the empty state" do
    sign_in_as('admin', 'admin')
    get near_miss_run_path(runs: 'no-such-run')
    assert_response :success
    assert_match 'No attempts found', response.body
  end

  test "show without runs redirects to the index" do
    sign_in_as('admin', 'admin')
    get near_miss_run_path
    assert_redirected_to near_miss_runs_path
  end

  # --- repair detail ---

  test "repair detail renders patch, rounds and links" do
    sign_in_as('admin', 'admin')
    get near_miss_repair_path(@repair)
    assert_response :success
    assert_match 'cstdint', response.body
    assert_match 'added missing include', response.body
    assert_match submission_path(@original.id), response.body
    assert_match submission_path(@shadow.id), response.body
    assert_select ".verdict-strip[data-comment='PP--']", count: 1, message: "original verdict strip"
    assert_select ".verdict-strip[data-comment='PPPP']", count: 1, message: "repaired verdict strip"
    assert_match 'syntax', response.body
  end

  test "repair detail for a failed attempt without shadow" do
    sign_in_as('admin', 'admin')
    get near_miss_repair_path(@failed)
    assert_response :success
    assert_match 'transport exploded', response.body
    assert_match 'no shadow', response.body
  end
end
