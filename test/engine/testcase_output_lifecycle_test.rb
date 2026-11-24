require 'test_helper'
require 'tmpdir'

# Regression guard for the 2026-08-30 fleet outage: rev 2045 put
# FileUtils.rm_f(stdout.txt) inside JudgeBase#prepare_testcase_directory to
# clear a stale output before a rerun — but that helper is shared, and
# Checker#process re-runs it *after* the evaluator has produced the output,
# so every testcase lost its stdout.txt between the run and the compare and
# every submission on every deployed server ended in grader_error.
#
# The rule these tests pin: prepare_testcase_directory only creates paths
# and never deletes; clearing a stale output is the Evaluator's job, done
# once, immediately before it runs the program.
#
# Only @problem_path / @submission_path are needed by the helper (normally
# filled by prepare_dataset_directory / prepare_submission_directory from a
# live Dataset + Submission); pointing them at a tmpdir is the smallest
# honest seam, as in checker_command_test.rb.
class TestcaseOutputLifecycleTest < ActiveSupport::TestCase
  FakeTestcase = Struct.new(:id) do
    def get_name_for_dir = id.to_s
  end

  setup do
    @dir = Pathname.new(Dir.mktmpdir('judge-'))
    @tc = FakeTestcase.new(7)
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  def judge(klass)
    j = klass.new('test-worker', 'test-box')
    j.instance_variable_set(:@problem_path, @dir + 'problem')
    j.instance_variable_set(:@submission_path, @dir + 'submission')
    j
  end

  def write_output(j)
    out = j.instance_variable_get(:@output_file)
    File.write(out, "42\n")
    out
  end

  test 'Checker re-preparing the testcase directory keeps the stdout.txt the evaluator wrote' do
    checker = judge(Checker)
    checker.prepare_testcase_directory(:sub, @tc)
    out = write_output(checker)

    checker.prepare_testcase_directory(:sub, @tc)

    assert_path_exists out, 'prepare_testcase_directory must not delete the submission output'
    assert_equal "42\n", File.read(out)
  end

  test 'Evaluator re-preparing the testcase directory keeps an existing stdout.txt too' do
    evaluator = judge(Evaluator)
    evaluator.prepare_testcase_directory(:sub, @tc)
    out = write_output(evaluator)

    evaluator.prepare_testcase_directory(:sub, @tc)

    assert_path_exists out
  end

  test 'Evaluator#clear_stale_output removes a leftover stdout.txt before the run' do
    evaluator = judge(Evaluator)
    evaluator.prepare_testcase_directory(:sub, @tc)
    out = write_output(evaluator)

    evaluator.clear_stale_output

    refute File.exist?(out), 'a stale output from an earlier run must be gone before isolate opens it'
    assert_path_exists out.dirname, 'only the file goes; the 0777 output dir stays for the bind mount'
  end

  test 'Evaluator#clear_stale_output is a no-op when there is nothing to clear' do
    evaluator = judge(Evaluator)
    evaluator.prepare_testcase_directory(:sub, @tc)

    assert_nothing_raised { evaluator.clear_stale_output }
  end
end
