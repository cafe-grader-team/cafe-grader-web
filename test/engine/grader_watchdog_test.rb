require 'test_helper'
require 'tmpdir'
require 'timeout'

# Grader.watchdog's decision logic, isolated from ps/spawn/kill so it can be
# exercised on canned process tables. Regression guard for the 2026-08-27
# duplicate-grader incident (see the method comments in app/engine/grader.rb).
class GraderWatchdogTest < ActiveSupport::TestCase
  KEY = 'c2f7966dee'

  # Modelled on real `ps -e -o pid,ppid,etimes,args` output from a deploy host:
  # every grader is an `sh -c` wrapper plus its Ruby child.
  PS = <<~PS
        PID    PPID ELAPSED COMMAND
          1       0   22567 /sbin/init
    1244304       1  315902 sh -c rails runner "Grader.start(1,:#{KEY})"
    1244306 1244304  315902 /usr/share/rvm/rubies/ruby-3.4.4/bin/ruby bin/rails runner Grader.start(1,:#{KEY})
    1244311       1  315902 sh -c rails runner "Grader.start(2,:#{KEY})"
    1244313 1244311  315902 /usr/share/rvm/rubies/ruby-3.4.4/bin/ruby bin/rails runner Grader.start(2,:#{KEY})
    1250000       1     120 /usr/share/rvm/rubies/ruby-3.4.4/bin/ruby bin/rails runner Grader.start(1,:#{KEY})
    1260000       1      60 /usr/share/rvm/rubies/ruby-3.4.4/bin/ruby bin/rails runner Grader.start(12,:#{KEY})
    1270000       1      30 /usr/share/rvm/rubies/ruby-3.4.4/bin/ruby bin/rails runner Grader.start(1,:otherkey)
    1280000       1       5 /bin/sh -c cd /home/dae/cafe_grader/web && bundle exec bin/rails runner -e production 'Grader.watchdog'
    1290000 1280000       5 ruby bin/rails runner -e production Grader.watchdog
    1300000       1       2 grep start([[:blank:]]*1[[:blank:]]*,[[:blank:]]*:#{KEY})$
  PS

  def pids(box, key = KEY)
    Grader.grader_processes(PS, box, key).map { |p| p[:pid] }
  end

  test 'collapses the sh -c wrapper chain to its Ruby leaf and lists oldest first' do
    assert_equal [1244306, 1250000], pids(1), 'wrapper 1244304 dropped; the newer duplicate 1250000 comes second'
    assert_equal [1244313], pids(2)
  end

  test 'matches the box id whole and the key exactly' do
    assert_equal [1260000], pids(12), 'box 12 must not be swallowed by box 1'
    refute_includes pids(1), 1270000, 'a grader started with another key is not ours'
    assert_empty pids(3)
    assert_empty pids(1, 'nope')
  end

  test 'ignores the watchdog itself and a stray grep of the old pattern' do
    all = (1..12).flat_map { |b| pids(b) }
    refute_includes all, 1280000
    refute_includes all, 1290000
    refute_includes all, 1300000
  end

  test 'header and unrelated rows never match' do
    assert_empty Grader.grader_processes("    PID    PPID ELAPSED COMMAND\n  1  0  5 /sbin/init\n", 1, KEY)
  end

  # --- plan_box -----------------------------------------------------------

  def procs(*pids)
    pids.each_with_index.map { |pid, i| {pid: pid, ppid: 1, elapsed: 1000 - i} }
  end

  test 'enabled box with no grader spawns one' do
    assert_equal [[:spawn]], Grader.plan_box(GraderProcess.new(enabled: true), [])
  end

  test 'enabled box with exactly one grader is left alone' do
    assert_empty Grader.plan_box(GraderProcess.new(enabled: true), procs(100))
  end

  test 'enabled box with duplicates TERMs every grader but the oldest' do
    plan = Grader.plan_box(GraderProcess.new(enabled: true), procs(100, 200, 300))
    assert_equal [[:term, 200], [:term, 300]], plan
    refute_includes plan.map(&:first), :kill, 'a grader that still beats is never KILLed — TERM lets it finish its job'
  end

  test 'enabled box whose grader has not beaten for 10 minutes KILLs it' do
    gp = GraderProcess.new(enabled: true, last_heartbeat: 11.minutes.ago)
    assert_equal [[:kill, 100]], Grader.plan_box(gp, procs(100)),
                 'a grader held inside one job; the next tick reclaims the job and respawns'
  end

  test 'enabled box with a recent heartbeat is left alone' do
    gp = GraderProcess.new(enabled: true, last_heartbeat: 9.minutes.ago)
    assert_empty Grader.plan_box(gp, procs(100))
  end

  test 'a grader younger than the stale heartbeat it inherited is not KILLed' do
    gp = GraderProcess.new(enabled: true, last_heartbeat: 3.days.ago)
    fresh = [{pid: 100, ppid: 1, elapsed: 120}]
    assert_empty Grader.plan_box(gp, fresh), 'spawned 2 minutes ago on a box disabled for days'
  end

  test 'disabled box TERMs all of its graders, not just the first' do
    gp = GraderProcess.new(enabled: false, last_heartbeat: 10.seconds.ago)
    assert_equal [[:term, 100], [:term, 200]], Grader.plan_box(gp, procs(100, 200))
  end

  test 'disabled box with a stale heartbeat KILLs' do
    gp = GraderProcess.new(enabled: false, last_heartbeat: 10.minutes.ago)
    assert_equal [[:kill, 100]], Grader.plan_box(gp, procs(100))
  end

  test 'disabled box with no heartbeat yet is stopped gracefully' do
    gp = GraderProcess.new(enabled: false, last_heartbeat: nil)
    assert_equal [[:term, 100]], Grader.plan_box(gp, procs(100))
  end

  test 'disabled box with nothing running does nothing' do
    assert_empty Grader.plan_box(GraderProcess.new(enabled: false), [])
  end

  # --- lock ---------------------------------------------------------------

  test 'a second watchdog skips while the first holds the lock' do
    ran = []
    first = Grader.with_watchdog_lock('test-lock') do
      ran << :first
      second = Grader.with_watchdog_lock('test-lock') { ran << :second }
      assert_equal false, second
    end
    assert_equal true, first
    assert_equal [:first], ran
    assert_equal true, Grader.with_watchdog_lock('test-lock') { ran << :after }, 'lock released on exit'
  end

  # --- spawn hygiene ------------------------------------------------------

  # Regression guard for the 2026-08-30 deploy hang: a grader spawned with only
  # :out/:err redirected inherited fd 6 (RVM's login-shell copy of stderr —
  # sshd's stderr pipe during a deploy) plus the watchdog's own mysql2 socket,
  # and held the ssh channel open long after the deploy script had finished.
  test 'a spawned grader gets /dev/null and its log file and nothing else' do
    skip 'needs /proc' unless File.directory?('/proc/self/fd')
    leaked_r, leaked_w = IO.pipe
    leaked_w.close_on_exec = false # stand-in for RVM's fd 6 and mysql2's socket
    Dir.mktmpdir do |dir|
      log = File.join(dir, 'grader-1.txt')
      pid = spawn('sleep 30', Grader.grader_spawn_options(log))
      begin
        # until the child has exec'd, /proc still shows the pre-exec fd table
        Timeout.timeout(5) { sleep 0.02 until File.read("/proc/#{pid}/comm").strip == 'sleep' }
        # Right after exec the child can briefly show a loader-transient
        # descriptor (fd 3) that closes between the directory listing and
        # readlink -> ENOENT (seen 1 in 5 spawns on WSL2, 2026-09-02). Sample
        # until the table settles to {0,1,2}; a real leak persists through
        # every sample and still fails the assertion below.
        fds = nil
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
        loop do
          begin
            fds = Dir.children("/proc/#{pid}/fd").map(&:to_i).sort.to_h { |n| [n, File.readlink("/proc/#{pid}/fd/#{n}")] }
            break if fds.keys.all? { |n| n <= 2 }
          rescue Errno::ENOENT
            # an fd vanished mid-snapshot: the child is still settling, sample again
          end
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          sleep 0.01
        end
        assert_equal({0 => File::NULL, 1 => log, 2 => log}, fds, 'leaked into the grader')
      ensure
        Process.kill('TERM', pid)
        Process.wait(pid)
      end
    end
  ensure
    leaked_r&.close
    leaked_w&.close
  end
end
