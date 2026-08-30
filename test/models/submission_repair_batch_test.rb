require 'test_helper'

class SubmissionRepairBatchTest < ActiveJob::TestCase
  setup do
    @original = submissions(:add1_by_john)
    @original.update_columns(status: Submission.statuses[:done], points: 40)
  end

  test "enqueue_batch! creates pending rows and enqueues jobs" do
    assert_enqueued_jobs 1, only: Llm::SubmissionRepairJob do
      result = SubmissionRepair.enqueue_batch!(
        submission_ids: [@original.id], budget_lines: 2, budget_chars: 20,
        rounds: 3, run_label: 'test-run')
      assert_equal({enqueued: 1, skipped: 0}, result)
    end
    r = SubmissionRepair.last
    assert r.pending?
    assert_equal @original.id, r.original_submission_id
    assert_equal 'test-run', r.run_label
  end

  test "enqueue_batch! is idempotent per run label (resume semantics)" do
    SubmissionRepair.enqueue_batch!(submission_ids: [@original.id], budget_lines: 2,
                                    budget_chars: 20, rounds: 3, run_label: 'r1')
    assert_no_enqueued_jobs only: Llm::SubmissionRepairJob do
      result = SubmissionRepair.enqueue_batch!(submission_ids: [@original.id], budget_lines: 2,
                                               budget_chars: 20, rounds: 3, run_label: 'r1')
      assert_equal({enqueued: 0, skipped: 1}, result)
    end
    assert_enqueued_jobs 1, only: Llm::SubmissionRepairJob do
      SubmissionRepair.enqueue_batch!(submission_ids: [@original.id], budget_lines: 2,
                                      budget_chars: 20, rounds: 3, run_label: 'r2')
    end
  end
end
