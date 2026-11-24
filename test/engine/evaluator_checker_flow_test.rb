require 'test_helper'
require 'tmpdir'

# The grading path the unit tests never crossed: Evaluator#execute running a
# testcase, then handing the output to Checker#process for the compare. Only
# the sandbox (IsolateRunner) and the two network fetches (dataset files,
# compiled binary) are replaced by minimal fakes; the judge directory layout,
# the checker's own re-prepare of that directory, the real `diff`, and the
# Evaluation row are the production code. Regression guard for the
# 2026-08-30 outage (rev 2045 deleted stdout.txt in the shared
# prepare_testcase_directory, which the checker re-runs after the program has
# written it): on that code this test fails with
#   RuntimeError: Output file [...]/stdout.txt does not exists
# and CI has no isolate, so nothing else would have.
class EvaluatorCheckerFlowTest < ActiveSupport::TestCase
  setup do
    @judge_dir = Dir.mktmpdir('judge-flow-')
    @worker_conf = Rails.configuration.worker
    @orig_judge_path = @worker_conf[:directory][:judge_path]
    @worker_conf[:directory][:judge_path] = @judge_dir
    @sub = submissions(:add1_by_admin)
    @tc  = testcases(:tc_add_1)
  end

  teardown do
    @worker_conf[:directory][:judge_path] = @orig_judge_path
    FileUtils.rm_rf(@judge_dir)
  end

  # An Evaluator whose sandbox "runs" the program by writing program_stdout
  # where isolate would have (the host dir bound to /output) and reports a
  # clean run, and whose downloads leave the testcase files where
  # download_dataset would have. Everything else is the real class.
  def evaluator_with_fake_sandbox(program_stdout:)
    ev = Evaluator.new('test-worker', 7)
    ev.define_singleton_method(:setup_isolate)   { |*| }
    ev.define_singleton_method(:cleanup_isolate) { |*| }
    ev.define_singleton_method(:prepare_executable) do
      @mybin_path = @bin_path + @box_id.to_s
      @mybin_path.mkpath
    end
    ev.define_singleton_method(:prepare_worker_dataset) do |dataset, _type|
      dataset.testcases.each do |t|
        prepare_testcase_directory(nil, t)
        File.write(@input_file, t.input)
        File.write(@ans_file, t.sol)
      end
    end
    ev.define_singleton_method(:run_isolate) do |prog, **_opts|
      next ['', '', nil, {}] if prog.start_with?('/usr/bin/chmod')   # the post-run chmod step
      File.write(@output_file, program_stdout)
      ['', "OK (0.010 sec real, 0.012 sec wall)\n", nil,
       {'time' => 0.01, 'time-wall' => 0.012, 'max-rss' => 1234, 'exitcode' => 0}]
    end
    ev
  end

  def evaluation
    Evaluation.find_by!(submission: @sub, testcase: @tc)
  end

  test 'a correct program output survives the checker re-prepare and is judged correct' do
    result = evaluator_with_fake_sandbox(program_stdout: @tc.sol).execute(@sub, @tc)

    assert_equal :success, result.status, "evaluator reported #{result.to_h}"
    assert_equal 'correct', evaluation.result
    stdout = Pathname.new(@judge_dir).join('isolate_submission', @sub.id.to_s, @tc.get_name_for_dir, 'output', 'stdout.txt')
    assert_path_exists stdout, 'the program output must still be on disk after the compare'
    assert_equal @tc.sol, File.read(stdout)
  end

  test 'a wrong program output is judged wrong by the real diff, not by the fake' do
    evaluator_with_fake_sandbox(program_stdout: "999\n").execute(@sub, @tc)

    assert_equal 'wrong', evaluation.result
  end

  # A rejudge while this testcase ran: the new chain owns the row now, so the
  # old chain's result is dropped and its job reports the supersede.
  test 'an evaluate job of a superseded chain writes no evaluation' do
    old_chain = Job.create!(job_type: :compile, arg: @sub.id, status: :success)
    Evaluation.where(submission: @sub).delete_all
    @sub.add_judge_job(@tc.dataset)

    result = evaluator_with_fake_sandbox(program_stdout: @tc.sol).execute(@sub, @tc, chain_id: old_chain.id)

    assert_equal :error, result.status
    assert_equal 'superseded by rejudge', result.result_description
    assert_nil Evaluation.find_by(submission: @sub, testcase: @tc)
  end

  test 'an evaluate job of the current chain writes its evaluation' do
    chain = Job.create!(job_type: :compile, arg: @sub.id, status: :success)
    result = evaluator_with_fake_sandbox(program_stdout: @tc.sol).execute(@sub, @tc, chain_id: chain.id)

    assert_equal :success, result.status
    assert_equal 'correct', evaluation.result
    assert_equal 1, Evaluation.where(submission: @sub, testcase: @tc).count
  end

  # A custom checker that never returns used to hold the grader box, and the
  # job, forever (Open3.capture3 has no bound). Now that testcase alone is a
  # grader error and the evaluate job completes.
  test 'a checker that hangs is cut off at the bound and marks only this testcase' do
    @worker_conf[:limits] = {checker_timeout: 1}
    dataset = @tc.dataset
    dataset.update!(evaluation_type: :custom_testlib)
    dataset.checker.attach(io: StringIO.new(''), filename: 'checker')
    ev = evaluator_with_fake_sandbox(program_stdout: @tc.sol)
    ev.define_singleton_method(:prepare_executable) do
      @mybin_path = @bin_path + @box_id.to_s
      @mybin_path.mkpath
      File.write(@prob_checker_file, "#!/bin/sh\nsleep 30\n")
      File.chmod(0o755, @prob_checker_file)
    end

    result = ev.execute(@sub, @tc)

    assert_equal :success, result.status, 'the evaluate job itself completes'
    assert_equal 'grader_error', evaluation.result
    assert_equal '(cafe-checker) checker timed out after 1 s', evaluation.result_text
  ensure
    @worker_conf.delete(:limits)
  end
end
