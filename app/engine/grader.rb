class Grader
  # This class is the main event loop for grader process
  # It is associated with one box-id of isolate
  # Responsible for dispatching a job

  JudgeProblemPath = 'isolate_problem'
  JudgeSubmissionPath = 'isolate_submission'
  JudgeSubmissionBinPath = 'bin'
  JudgeSubmissionSourcePath = 'source'
  JudgeSubmissionLibPath = 'lib'
  JudgeSubmissionCompilePath = 'compile'
  JUDGE_SUB_COMPILE_RESULT_PATH = 'compile_result'
  JUDGE_MANAGER_PATH = 'source_manager'

  include JudgeBase

  attr_accessor :job
  attr_reader :box_id

  def initialize(worker_id, box_id, key = Rails.configuration.worker[:server_key])
    @box_id = box_id
    @worker_id = worker_id
    @grader_process = GraderProcess.find_or_create_by(box_id: box_id, worker_id: worker_id)
    @grader_process.update(key: key)
    @last_job_time = Time.zone.now
    Rainbow.enabled = true
    judge_log "Grader created with key #{key}"
  end

  #
  # ---- job processing ---
  #

  def process_job_compile
    sub = Submission.find(@job.arg)
    param = JSON.parse(@job.param, symbolize_names: true)
    dataset = Dataset.find(param[:dataset_id])

    compiler = Compiler.get_compiler(sub).new(@worker_id, @box_id)
    result = compiler.compile(sub, dataset)

    # report compile
    judge_log "#{@job.to_text} completed with result #{result.to_h}"
    @job.report(result)

    # add next jobs only when compilation succeeded
    if sub.compilation_success?
      if dataset.testcases.count > 0
        Job.add_evaluation_jobs(sub, dataset, @job.id, @job.priority)
      else
        # no testcase
        sub.update(status: :done, points: 0, grader_comment: 'No testcase', graded_at: Time.zone.now)
      end
    end
  end

  def process_job_evaluate
    sub = Submission.find(@job.arg)
    param = JSON.parse(@job.param, symbolize_names: true)
    testcase = Testcase.find(param[:testcase_id])

    evaluator = Evaluator.get_evaluator(sub).new(@worker_id, @box_id)
    result = evaluator.execute(sub, testcase)

    @job.report(result)

    # add scoring when all evaluation is done
    if Job.all_evaluate_job_complete(@job)
      # scoring job has higher priority
      Job.add_scoring_job(sub, testcase.dataset, @job.parent_job_id, @job.priority + 1)
    end
  end

  def process_job_scoring
    sub = Submission.find(@job.arg)
    param = JSON.parse(@job.param, symbolize_names: true)
    dataset = Dataset.find(param[:dataset_id])

    scorer = Scorer.get_scorer(sub).new(@worker_id, @box_id)
    result = scorer.process(sub, dataset)

    @job.report(result)
  end

  #
  # -------- main job running function --------------
  #
  def check_and_run_job
    @job = Job.take_oldest_waiting_job(@grader_process, @grader_process.job_type_array) if Job.has_waiting_job

    if @job
      @last_job_time = Time.zone.now
      begin
        judge_log "Processing #{@job.to_text}"
        @grader_process.update(task_id: @job.id, status: :working)
        if @job.jt_compile?
          process_job_compile
        elsif @job.jt_evaluate?
          process_job_evaluate
        elsif @job.jt_score?
          process_job_scoring
        else
          # we don't know how to process this job, report so
          @job.report({status: :error, result_description: 'grader does not have handler for this job_type'})
        end
      rescue GraderError, ActiveRecord::RecordNotFound => ge
        # When the job raise an error, log the error and set
        # the main comment to the error message (so that the user can see it)
        judge_log Rainbow('(GraderError)').bg(COLOR_ERROR).color(:yellow) + " " + ge.message, Logger::ERROR
        @job.update(status: :error, result: ge.message) if ge.end_job
        if ge.update_submission
          s = Submission.find(ge.submission_id)
          s.set_grading_error(ge.message_for_user)
        end
      rescue => e
        judge_log Rainbow('(ERROR)').bg(COLOR_ERROR).color(:black) + " #{e.class}: #{e.message}", Logger::ERROR
        judge_log e.backtrace&.first(5)&.join("\n"), Logger::ERROR
        # retry up to 3 times, then mark as error to prevent infinite loop
        retry_count = (@job.result&.match(/retry (\d+)/)&.[](1)&.to_i || 0) + 1
        if retry_count < 3
          @job.update(status: :wait, result: "retry #{retry_count}: #{e.class}: #{e.message}")
        else
          @job.update(status: :error, result: "gave up after #{retry_count} retries: #{e.class}: #{e.message}")
          s = Submission.find_by(id: @job.arg)
          s&.set_grading_error("Internal grading error after #{retry_count} retries, please rejudge.")
        end
      end
      result = true
    else
      result = false
    end
    @job = nil
    return result
  end

  def main_loop
    last_heartbeat = Time.zone.now
    running = true

    # trap signal
    Signal.trap("TERM") do
      puts "got TERM signal, next iteration of main loop will be stopped"
      running = false
    end

    # THE MAIN LOOP
    while running do
      # fetch any job
      result = check_and_run_job

      # heartbeat
      current = Time.zone.now
      if current - last_heartbeat > 3.0
        last_heartbeat = current
        @grader_process.update(last_heartbeat: current, status: (Time.zone.now - @last_job_time > 5.second) ? :idle : :working)

        # check if the database tell us to stop
        @grader_process.reload
        running = @grader_process.enabled
      end

      if result
        # if we have done something just sleep for a very short time
        sleep (0.01)
      else
        # if no job is found, we sleep

        # 5 Hz
        sleep (0.2)
      end
    end
  end

  # start the main loop, with the given box_id
  # Key should be unique to each main web app server
  # and should be in worker.yml
  def self.start(box_id, key)
    # load parameter
    g = Grader.new(Rails.configuration.worker[:worker_id], box_id, key)

    # trying to connect to server, register as a new grader process

    # successfully connected, enter the loop
    puts "--------  grader main loop started #{Time.zone.now} --------"
    g.main_loop
    puts "grader main loop exit gracefully at #{Time.zone.now}"
  end

  # Watchdog — run by cron every minute (config/schedule.rb). Reconciles this
  # worker's GraderProcess rows with the grader processes actually running:
  # spawns what is missing, stops what should not run, and — since the
  # 2026-08-27 ISE incident — stops duplicates. Two orphaned crontab blocks
  # (whenever identified them by the schedule.rb path, and the app dir had
  # been renamed) ran two watchdogs per minute; both saw "no grader" for a
  # box and both spawned one, and `lines.count >= 1` then read the pair as
  # healthy forever. Two graders on one isolate box collide ("This box is
  # currently in use"), stored as grader_error (`!`) — silent score deflation.
  # Defences, in order: a host-wide flock so two watchdogs cannot race the ps
  # check; duplicates are detected and the extras TERMed; the deploy pipeline
  # gives whenever a stable identifier (automation repo).
  def self.watchdog
    worker_id  = Rails.configuration.worker[:worker_id]
    server_key = Rails.configuration.worker[:server_key]

    with_watchdog_lock(worker_id) do
      ps_text = `ps -e -o pid,ppid,etimes,args`
      GraderProcess.where(worker_id: worker_id).each do |gp|
        procs = grader_processes(ps_text, gp.box_id, server_key)
        pids  = procs.map { |p| p[:pid] }
        puts "grader process with box_id #{gp.box_id}: #{procs.size} running#{pids.any? ? " (pid #{pids.join(', ')})" : ''}"

        plan_box(gp, procs).each do |action, pid|
          case action
          when :spawn
            stdout_file = Rails.configuration.worker[:directory][:grader_stdout_base_file] + gp.box_id.to_s + '.txt'
            cmd = "rails runner \"Grader.start(#{gp.box_id},:#{server_key})\""
            spawn(cmd, [:out, :err] => [stdout_file, 'a'])
            puts "spawning new grader main loop with #{cmd}, redirecting :out,:err to #{stdout_file}"
          when :term
            if gp.enabled
              msg = "box #{gp.box_id} has #{procs.size} graders — sending TERM to duplicate #{pid}, keeping the oldest (#{pids.first})"
              puts msg
              Rails.logger.warn("[Grader.watchdog] #{msg}")
            else
              puts "sending TERM signal to #{pid} (box_id #{gp.box_id})"
            end
            signal_grader('TERM', pid)
          when :kill
            puts "sending KILL signal to stalled process #{pid} (box_id #{gp.box_id})"
            signal_grader('KILL', pid)
          end
        end
      end
    end
  end

  # The grader processes serving one box, parsed from
  # `ps -e -o pid,ppid,etimes,args` output: [{pid:, ppid:, elapsed:}], oldest
  # first. On every deploy host a grader is a two-process chain —
  # `sh -c rails runner "Grader.start(N,:key)"` and its Ruby child (dash does
  # not exec-optimise the quoted command) — so a match whose child is also a
  # match is a wrapper and is dropped: signals must reach the Ruby leaf, the
  # process that traps TERM. The box id is matched whole (`1` is not `12`) and
  # the key exactly; the watchdog's own `Grader.watchdog` line never matches.
  def self.grader_processes(ps_text, box_id, key)
    pattern = /Grader\.start\([[:blank:]]*#{Regexp.escape(box_id.to_s)}[[:blank:]]*,[[:blank:]]*:#{Regexp.escape(key.to_s)}[[:blank:]]*\)["']?[[:blank:]]*\z/
    procs = ps_text.each_line.filter_map do |line|
      pid, ppid, elapsed, args = line.strip.split(/[[:blank:]]+/, 4)
      next unless args && pid.match?(/\A\d+\z/) && args.match?(pattern)
      {pid: pid.to_i, ppid: ppid.to_i, elapsed: elapsed.to_i}
    end
    leaves = procs.reject { |p| procs.any? { |c| c[:ppid] == p[:pid] } }
    leaves.sort_by { |p| -p[:elapsed] }
  end

  # What the watchdog should do for one GraderProcess row given the processes
  # serving its box (oldest first). Returns [[action, pid], ...]:
  #   [:spawn]       enabled, nothing running
  #   [:term, pid]   enabled: a duplicate (every process but the oldest);
  #                  disabled: graceful stop. TERM, never KILL, for a live
  #                  grader — main_loop finishes its current job first, and a
  #                  Job left in :process is never reclaimed (doc/backlog.md).
  #   [:kill, pid]   disabled and the heartbeat is stale (> 300 s)
  def self.plan_box(gp, procs)
    if gp.enabled
      return [[:spawn]] if procs.empty?
      procs.drop(1).map { |p| [:term, p[:pid]] }
    else
      stalled = gp.last_heartbeat.present? && gp.last_heartbeat < 300.seconds.ago
      procs.map { |p| [stalled ? :kill : :term, p[:pid]] }
    end
  end

  # Host-wide and non-blocking: a second watchdog in the same minute (a stray
  # crontab block, a manual `Grader.restart`) skips instead of racing the ps
  # check. Lives in Dir.tmpdir rather than Rails.root/tmp so two checkouts of
  # the app on one host — exactly the incident's shape — share one lock.
  def self.with_watchdog_lock(worker_id)
    path = File.join(Dir.tmpdir, "cafe-grader-watchdog-#{worker_id}.lock")
    File.open(path, File::RDWR | File::CREAT, 0644) do |lock|
      unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        puts "another watchdog holds #{path}; skipping this run"
        return false
      end
      yield
      true
    end
  end

  def self.signal_grader(sig, pid)
    Process.kill(sig, pid)
  rescue Errno::ESRCH
    puts "process #{pid} is already gone"
  end

  def self.make_enabled(num)
    worker_id = Rails.configuration.worker[:worker_id]
    server_key = Rails.configuration.worker[:server_key]
    (1..num).each do |box_id|
      gp = GraderProcess.find_or_create_by(worker_id: worker_id, box_id: box_id)
      gp.update(key: server_key, enabled: true)
    end
    GraderProcess.where(worker_id: worker_id).where.not(box_id: 1..num).update_all(enabled: false)
  end


  # for testing and migrate
  def self.restart(num = -1)
    if num == -1
      num = GraderProcess.where(worker_id: Rails.configuration.worker[:worker_id], enabled: true).pluck('MAX(box_id)').first || 1
    end
    make_enabled(0)
    watchdog
    sleep(1)
    puts '-------------'
    make_enabled(num)
    watchdog
  end

  # should run via cron everyday
  # it will cleanup anything older than *ago* minutes
  def self.cleanup_web(ago_min = 60*24)
    # clean old job
    Job.clean_old_job(ago_min.minutes)

    # purge compiled file
    Submission.where(status: 'done').where('graded_at < ?', Time.zone.now - ago_min.minutes).joins(:compiled_files_attachments).each do |s|
      s.compiled_files.purge
    end
  end

  def self.cleanup_judge(ago_min = 60*24)
    # delete old submission dir that is older than 12 hour
    isolate_sub_path = Pathname.new(Rails.configuration.worker[:directory][:judge_path]) + Grader::JudgeSubmissionPath
    cmd = "find #{isolate_sub_path} -maxdepth 1 -mmin +#{ago_min} -exec rm -rf {} \\;"
    puts "executing #{cmd}"
    spawn(cmd)
  end
end
