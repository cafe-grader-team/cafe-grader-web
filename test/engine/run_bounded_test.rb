require 'test_helper'
require 'tmpdir'

# JudgeBase#run_bounded: the wall-clock bound on the dataset programs that run
# on the judge host outside isolate (checker, initializer). Before it, both
# ran under Open3.capture3 / system with no bound, so one checker stuck in a
# loop held its grader box, and the job, forever.
class RunBoundedTest < ActiveSupport::TestCase
  class Judge
    include JudgeBase
  end

  setup do
    @judge = Judge.new('test-worker', 7)
    @worker_conf = Rails.configuration.worker
  end

  teardown do
    @worker_conf.delete(:limits)
  end

  def gone_or_zombie?(pid)
    File.read("/proc/#{pid}/stat").split[2] == 'Z'
  rescue Errno::ENOENT
    true
  end

  test 'a command that finishes in time returns its output and status' do
    out, err, status, timed_out = @judge.run_bounded(['sh', '-c', 'echo out; echo err >&2; exit 3'], timeout: 5)
    assert_equal "out\n", out
    assert_equal "err\n", err
    assert_equal 3, status.exitstatus
    assert_equal false, timed_out
  end

  test 'a command past the bound is killed with everything it forked' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # the shell prints its background child's pid, then waits on it
    out, _err, status, timed_out = @judge.run_bounded(['sh', '-c', 'sleep 30 & echo $!; wait'], timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert timed_out
    assert_operator elapsed, :<, 5, 'returned soon after the bound, not after the sleep'
    assert_equal 'KILL', Signal.signame(status.termsig)
    grandchild = out.to_i
    assert_operator grandchild, :>, 0
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    sleep 0.05 until gone_or_zombie?(grandchild) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    assert gone_or_zombie?(grandchild), 'the forked sleep must die with its process group'
  end

  test 'an initializer past its bound raises a GraderError for the submission' do
    @worker_conf[:limits] = {initializer_timeout: 1}
    orig_judge_path = @worker_conf[:directory][:judge_path]
    Dir.mktmpdir do |dir|
      @worker_conf[:directory][:judge_path] = dir
      dataset = datasets(:ds_add)
      dataset.update!(initializer_filename: 'init.sh')
      @judge.prepare_dataset_directory(dataset)
      init = Pathname.new(dir).join('isolate_problem', dataset.problem.id.to_s, "dsid_#{dataset.id}", 'initializers', 'init.sh')
      File.write(init, "#!/bin/sh\nsleep 30\n")
      File.chmod(0o755, init)

      error = assert_raises(GraderError) { @judge.run_initializer(dataset) }
      assert_equal 'dataset initializer timed out after 1 s', error.message
    end
  ensure
    @worker_conf[:directory][:judge_path] = orig_judge_path
  end
end
