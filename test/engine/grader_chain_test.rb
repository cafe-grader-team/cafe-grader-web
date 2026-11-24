require 'test_helper'

# A rejudge (Submission#add_judge_job) starts a new job chain while the old
# one may still be running. The grader checks the chain after it claims a job
# and the scorer before it writes the grade, so the old chain stops instead
# of writing over the new one.
class GraderChainTest < ActiveSupport::TestCase
  setup do
    @sub = submissions(:add1_by_admin)
    @dataset = datasets(:ds_add)
  end

  test 'a claimed job of a superseded chain is marked superseded and not run' do
    old_compile = Job.create!(job_type: :compile, arg: @sub.id, status: :success)
    # queued by the old compile after the rejudge had already run supersede!
    late = Job.create!(job_type: :evaluate, arg: @sub.id, parent_job_id: old_compile.id, status: :wait, priority: 1000,
                       param: {testcase_id: testcases(:tc_add_1).id}.to_json)
    Job.create!(job_type: :compile, arg: @sub.id, status: :wait)

    grader = Grader.new('test-worker', 97, 'test-key')
    grader.define_singleton_method(:process_job_evaluate) { raise 'a superseded job must not run' }
    assert grader.check_and_run_job

    assert_equal 'error', late.reload.status
    assert_equal 'superseded by rejudge', late.result
  end

  test 'the score job of a superseded chain leaves the submission alone' do
    old_compile = Job.create!(job_type: :compile, arg: @sub.id, status: :success)
    @sub.add_judge_job(@dataset)

    result = Scorer.new('test-worker', 97).process(@sub, @dataset, chain_id: old_compile.id)

    assert_equal :error, result.status
    assert_equal 'submitted', @sub.reload.status, 'not "Evaluations are missing" on the new grading'
    assert_nil @sub.grader_comment
  end
end
