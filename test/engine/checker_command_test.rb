require 'test_helper'

# Regression guard for the argv-order trap: CMS invokes its checker as
# (input, correct, USER) (cms/grading/steps/trusted.py), while cafe's
# custom_testlib evaluator (named custom_cms until rev 2047) follows the
# testlib/Codeforces order (input, USER, correct). cms_comparator exists
# specifically to match CMS's own order for tasks imported from CMS,
# without disturbing custom_testlib for the cafe problems that depend on
# its order (every deployed one, verified 2026-08-29/30).
#
# Checker#check_command only needs the ivars JudgeBase#initialize sets
# (@worker_id, @box_id) plus @prob_checker_file, which is normally filled
# in by prepare_dataset_directory (itself driven by a live Dataset +
# on-disk judge paths). Poking @prob_checker_file directly via
# instance_variable_set is the smallest honest seam here: check_command
# is a pure argv-builder over ivars/params, and standing up a full
# Dataset/Testcase/Submission fixture chain plus isolate/judge directories
# just to exercise argv-order string formatting would be testing the
# fixtures, not the bug.
class CheckerCommandTest < ActiveSupport::TestCase
  setup do
    @checker = Checker.new('test-worker', 'test-box')
    @checker.instance_variable_set(:@prob_checker_file, 'CHECKER')
  end

  test 'cms_comparator orders argv as input, correct, user (CMS-native)' do
    cmd = @checker.check_command('cms_comparator', 'INPUT', 'OUTPUT', 'ANS')
    assert_equal %w[CHECKER INPUT ANS OUTPUT], cmd
  end

  test 'custom_testlib keeps the testlib argv order: input, user, correct' do
    cmd = @checker.check_command('custom_testlib', 'INPUT', 'OUTPUT', 'ANS')
    assert_equal %w[CHECKER INPUT OUTPUT ANS], cmd
  end

  test 'custom_testlib_raw uses the same argv order as custom_testlib' do
    cmd = @checker.check_command('custom_testlib_raw', 'INPUT', 'OUTPUT', 'ANS')
    assert_equal %w[CHECKER INPUT OUTPUT ANS], cmd
  end

  # Issue #49: the checker keeps its uploaded filename on the judge host, and
  # "checker (1)" inside a shell command string was parsed by the shell. The
  # argv form hands the name to exec untouched.
  test 'a checker filename with a space and parentheses survives as one argv element' do
    @checker.instance_variable_set(:@prob_checker_file, Pathname.new('/judge/dsid_7/checker/checker (1)'))
    cmd = @checker.check_command('custom_testlib', 'INPUT', 'OUTPUT', 'ANS')
    assert_equal ['/judge/dsid_7/checker/checker (1)', 'INPUT', 'OUTPUT', 'ANS'], cmd
  end

  test 'such a checker actually runs: the argv reaches exec without a shell' do
    Dir.mktmpdir do |dir|
      checker = Pathname.new(dir).join('checker (1)')
      File.write(checker, "#!/bin/sh\necho \"$2|$3\"\n")
      File.chmod(0o755, checker)
      @checker.instance_variable_set(:@prob_checker_file, checker)
      out, _err, status = Open3.capture3(*@checker.check_command('cms_comparator', 'in.txt', 'out.txt', 'ans.txt'))
      assert status.success?
      assert_equal "ans.txt|out.txt\n", out
    end
  end

  test 'custom_cafe passes language, testcase number and the trailing 10 as strings' do
    @checker.instance_variable_set(:@sub, Struct.new(:language).new(Struct.new(:name).new('cpp')))
    @checker.instance_variable_set(:@testcase, Struct.new(:num).new(3))
    cmd = @checker.check_command('custom_cafe', 'INPUT', 'OUTPUT', 'ANS')
    assert_equal %w[CHECKER cpp 3 INPUT OUTPUT ANS 10], cmd
  end

  test 'the built-in diff evaluators are argv too, with Pathname arguments stringified' do
    cmd = @checker.check_command('default', Pathname.new('IN'), Pathname.new('OUT'), Pathname.new('ANS'))
    assert_equal %w[diff -q -b -B -Z OUT ANS], cmd
    assert_equal %w[diff -q OUT ANS], @checker.check_command('exact', 'IN', 'OUT', 'ANS')
    assert_equal [], @checker.check_command('no_check', 'IN', 'OUT', 'ANS')
  end
end
