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

  # watchdog, this function should be runs by cron every few minutes
  def self.watchdog
    worker_id = Rails.configuration.worker[:worker_id]
    server_key = Rails.configuration.worker[:server_key]

    GraderProcess.where(worker_id: worker_id).each do |gp|
      # check running status
      escaped_key = Shellwords.escape(server_key.to_s)
      grader_process = `ps -e -o pid,args | grep "start([[:blank:]]*#{gp.box_id}[[:blank:]]*,[[:blank:]]*:#{escaped_key})$" | grep Grader`
      running = grader_process.lines.count >= 1
      puts "grader process with box_id #{gp.box_id} is #{running ? 'found' : 'not found'}"
      if gp.enabled
        # we should have running grader of this box id
        if !running
          # start it
          stdout_file = Rails.configuration.worker[:directory][:grader_stdout_base_file] + gp.box_id.to_s + '.txt'
          cmd = "rails runner \"Grader.start(#{gp.box_id},:#{server_key})\""
          spawn(cmd, [:out, :err] => [stdout_file, 'a'])

          puts "spawning new grader main loop with #{cmd}, redirecting :out,:err to #{stdout_file}"
        end
      else
        # the process should NOT be running, send TERM to stop gracefully
        if running
          pid = grader_process.split[0].to_i
          stalled = gp.last_heartbeat.present? && gp.last_heartbeat < 300.seconds.ago
          if stalled
            puts "sending KILL signal to stalled process #{pid} (box_id #{gp.box_id})"
            Process.kill("KILL", pid)
          else
            puts "sending TERM signal to #{pid} (box_id #{gp.box_id})"
            Process.kill("TERM", pid)
          end
        end
      end
    end
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
