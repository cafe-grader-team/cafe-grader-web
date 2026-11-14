# There are multiple "prepare_xxx" method which set up directory and fill it with necessary file
# either by downloading or write them directly from the database
#
# prepare_submission_directory(sub)           This setups various Pathnames for that specific submission
# prepare_dataset_directory(dataset)          This setups various Pathnames for the problem's dataset
# prepare_worker_dataset(dataset, type)       This actually downloads managers/testcases/checker for the problem's dataset
#                                             It also call prepare_dataset_directory FIRST
# prepare_testcase_directory(sub,testcase)    This setups various Pathname for specific testcase
require 'open3'

module JudgeBase
  # Wall-clock bounds, in seconds, for the dataset programs that run on the
  # judge host outside isolate: the checker (per testcase) and the
  # initializer (once per dataset per worker). A host overrides them in
  # worker.yml under `limits:` (see worker.yml.SAMPLE); these are the defaults.
  CHECKER_TIMEOUT = 30
  INITIALIZER_TIMEOUT = 120

  INPUT_FILENAME = 'input.txt'
  STDOUT_FILENAME = 'stdout.txt'
  StdErrFilename = 'stderr.txt'
  AnsFilename = 'answer.txt'

  COMPILE_RESULT_STDOUT_FILENAME = 'compile_output'
  COMPILE_RESULT_STDERR_FILENAME = 'compile_err'
  COMPILE_RESULT_META_FILENAME = 'compile_meta'

  ISOLATE_BIN_PATH = 'mybin'
  ISOLATE_SOURCE_PATH = 'source'
  ISOLATE_SOURCE_MANAGER_PATH = 'source_manager'
  ISOLATE_INPUT_PATH = 'input'
  ISOLATE_OUTPUT_PATH = 'output'
  ISOLATE_DATA_PATH = 'data'

  # color for Rainbow
  COLOR_SUB = :skyblue
  COLOR_TESTCASE = :salmon
  COLOR_PROB = :deepink
  COLOR_COMPILE_SUCCESS = :lawngreen
  COLOR_COMPILE_ERROR = :deeppink
  COLOR_EVALUATION_DONE = :yellowgreen
  COLOR_EVALUATION_FORCE_EXIT = :orangered
  COLOR_GRADING_CORRECT = :seagreen
  COLOR_GRADING_WRONG = :crimson
  COLOR_GRADING_PARTIAL = :mediumpurple
  COLOR_SCORE_RESULT = :orange
  COLOR_ERROR = :darkred
  COLOR_ISOLATE_CMD = :darkslategray
  COLOR_CHECK_CMD = :indianred

  def initialize(worker_id, box_id)
    @worker_id = worker_id
    @box_id = box_id

    judge_log "#{self.class} created"
  end

  def isolate_need_cg_by_lang(language_name)
    case language_name
    when 'java', 'digital', 'go', 'python'
      true
    else
      false
    end
  end

  # Extra isolate options for a language, applied to both the compile and the
  # run sandbox: the built-in ones below, then whatever this host adds in
  # worker.yml under `isolate_options: <language>:` (see worker.yml.SAMPLE).
  # The host part is for what depends on the machine, not on the language —
  # e.g. Debian/Ubuntu's OpenJDK keeps its conf files in /etc/java-<N>-openjdk,
  # which the sandbox does not see unless it is mounted. Nothing is detected
  # here: `bin/rails engine:detect` works the host part out and writes it to
  # worker.yml, so what a grader uses is always readable in that file.
  def isolate_options_by_lang(language_name)
    [builtin_isolate_options(language_name), host_isolate_options(language_name)].reject(&:blank?).join(' ')
  end

  def host_isolate_options(language_name)
    Rails.configuration.worker.dig(:isolate_options, language_name.to_sym).to_s.strip
  end

  # Extra compiler command-line options this host needs for a language, from
  # worker.yml `compiler_options: <language>:` — the compiler-flag counterpart
  # of host_isolate_options, for what cannot be solved by a mount. Written by
  # `bin/rails engine:detect` too. Only Compiler::Pascal reads it today: fpc
  # learns its unit path from /etc/fpc.cfg, a single file the sandbox cannot
  # mount (isolate binds directories only).
  def host_compiler_options(language_name)
    Rails.configuration.worker.dig(:compiler_options, language_name.to_sym).to_s.strip
  end

  def builtin_isolate_options(language_name)
    case language_name
    when 'pas', 'php'
      '-d /etc/alternatives'
    when 'python'
      '-p -d /venv -E HOME -d /etc/alternatives'
    when 'java'
      '-p -d /etc/alternatives'
    when 'haskell'
      # -p: the runtime of GHC 9.x starts a timer thread at program start, and
      # isolate allows a single process/thread without it — every run died
      # with "Ticker: Failed to spawn thread" (signal 6) from the judge hosts'
      # move to Ubuntu 24.04 in 2025-07 until 2026-11.
      '-p -d /var/lib/ghc -d /tmp:rw'
    when 'digital'
      "-p -d /etc -d /tmp:rw -d /my_lib=#{Pathname.new(Rails.configuration.worker[:compiler][:digital]).dirname}"
    when 'rust'
      '-p -d /etc/alternatives'
    when 'go'
      # --open-files: isolate caps the sandbox at 64 open files by default;
      # `go build` of anything importing fmt/os runs out ("pipe2: too many
      # open files", issue #40). Applies to the run phase too — harmless.
      '-p -d /gocache:tmp --env=GOCACHE=/gocache --open-files=1024'
    when 'postgres'
      '-p --share-net'
    else
      ''
    end
  end

  # CPU seconds a compile may use (isolate -t counts every thread of every
  # process). Go gets more: its build cache is a fresh tmpfs per compile
  # (GOCACHE=/gocache, see the options above), so each `go build` first
  # compiles the standard library — 6.8 CPU seconds for a five-line program on
  # a 32-core dev machine with the judge host's Go 1.22 (2 s of wall clock);
  # on the judge host, under load, compiles crossed the
  # common 10 and came back as "Time limit exceeded" (4 of the last 6 Go
  # submissions on cp-grader, 2026-10).
  COMPILE_TIME_LIMIT = 10
  GO_COMPILE_TIME_LIMIT = 30

  def compile_time_limit_by_lang(language_name)
    language_name == 'go' ? GO_COMPILE_TIME_LIMIT : COMPILE_TIME_LIMIT
  end

  # return true when we must redirect the input into stdin
  def input_redirect_by_lang(language_name)
    case language_name
    when 'digital'
      return false
    else
      return true
    end
  end

  # download (via worker controller) files from the web server at url
  # and save to dest (which is a Pathname), raise exception on any error
  def download_from_web(url, dest, download_type: 'generic', chmod_mode: nil)
    begin
      uri = URI(url)

      # alias var
      hostname = uri.hostname
      port = uri.port
      basename = dest.basename

      # req
      req = Net::HTTP::Post.new(uri)
      req['x-api-key'] = Rails.configuration.worker[:worker_passcode]

      # do the request
      Net::HTTP.start(hostname, port) do |http|
        resp = http.request(req)
        if resp.kind_of?(Net::HTTPSuccess)
          File.open(dest.to_s, 'w:ASCII-8BIT') { |f| f.write(resp.body) }
          FileUtils.chmod(chmod_mode, dest) unless chmod_mode.nil?
          judge_log "Successful downloading of #{download_type} #{basename} from the server"
        else
          judge_log "Error downloading #{download_type} #{basename} from the server"
          # raise the exception
          resp.value
        end
      end
    rescue Net::HTTPExceptions => he
      raise GraderError.new("Error download #{download_type} \"#{he}\"", submission_id: @sub&.id)
    end
  end

  # set up directory and path/filename of the submission directory
  def prepare_submission_directory(sub)
    # preparing path name
    @submission_path = Pathname.new(Rails.configuration.worker[:directory][:judge_path]) + Grader::JudgeSubmissionPath + sub.id.to_s
    @compile_path = @submission_path + Grader::JudgeSubmissionCompilePath
    @compile_result_path = @submission_path + Grader::JUDGE_SUB_COMPILE_RESULT_PATH
    @bin_path = @submission_path + Grader::JudgeSubmissionBinPath
    @source_path = @submission_path + Grader::JudgeSubmissionSourcePath
    @manager_path = @submission_path + Grader::JUDGE_MANAGER_PATH
    @lib_path = @submission_path + Grader::JudgeSubmissionLibPath

    # prepare folder
    @compile_path.mkpath
    @compile_path.chmod(0777)
    @compile_result_path.mkpath
    @bin_path.mkpath
    @bin_path.chmod(0777)
    @source_path.mkpath
    @manager_path.mkpath
    @lib_path.mkpath

    # prepare path name inside isolate
    @isolate_bin_path = Pathname.new('/'+ISOLATE_BIN_PATH)
    @isolate_source_path = Pathname.new('/'+ISOLATE_SOURCE_PATH)
    @isolate_source_manager_path = Pathname.new('/'+ISOLATE_SOURCE_MANAGER_PATH)
    @isolate_input_path = Pathname.new('/'+ISOLATE_INPUT_PATH)
    @isolate_input_file = @isolate_input_path + INPUT_FILENAME
    @isolate_output_path = Pathname.new('/'+ISOLATE_OUTPUT_PATH)
    @isolate_stdout_file = @isolate_output_path + STDOUT_FILENAME
    @isolate_data_path = Pathname.new('/'+ISOLATE_DATA_PATH)
  end

  # set up directory and path/filename of the dataset
  # (including path for testcases/managers/checker/initializers)
  def prepare_dataset_directory(dataset)
    # preparing path name variable
    # base path
    @problem_path = Pathname.new(Rails.configuration.worker[:directory][:judge_path]) + Grader::JudgeProblemPath + dataset.problem.id.to_s
    @ds_path = @problem_path + ('dsid_'+dataset.id.to_s)

    # checker path
    @prob_checker_path = @ds_path + 'checker'
    @prob_checker_file = @prob_checker_path + dataset.checker.filename.to_s if dataset.checker.attached?

    # data path
    @prob_data_path = @ds_path + 'data'

    # manager path
    @manager_path = @ds_path + Grader::JUDGE_MANAGER_PATH

    # init path and file
    @prob_init_path = @ds_path + 'initializers'
    @prob_init_file = @prob_init_path + dataset.initializer_filename if dataset.initializer_filename
    @prob_init_work_path =  @ds_path + 'init_workspace'
    # TODO: fix this hardcode
    @prob_config_file = @prob_init_path + 'postgresql_config.yml'

    # prepare folder
    @ds_path.mkpath
    @prob_checker_path.mkpath
    @manager_path.mkpath
    @prob_init_path.mkpath
    @prob_init_work_path.mkpath
    @prob_data_path.mkpath
  end


  # download and set up dataset on this worker
  # including run of initialization script
  def download_dataset(dataset, type)
    prepare_dataset_directory(dataset)

    # download checker, managers, initializers, data,
    if type == :managers
      if dataset.checker.attached?
        url = Rails.configuration.worker[:hosts][:web]+worker_get_attachment_path(dataset.checker.id)
        download_from_web(url, @prob_checker_file, download_type: 'checker', chmod_mode: 0755)
      end

      # download any managers
      dataset.managers.each do |mng|
        basename = mng.filename.base + mng.filename.extension_with_delimiter
        dest = @manager_path + basename
        url = Rails.configuration.worker[:hosts][:web]+worker_get_attachment_path(mng.id)
        download_from_web(url, dest, download_type: 'manager')
      end

      # download any initializers
      dataset.initializers.each do |init|
        basename = init.filename.base + init.filename.extension_with_delimiter
        dest = @prob_init_path + basename
        url = Rails.configuration.worker[:hosts][:web]+worker_get_attachment_path(init.id)
        download_from_web(url, dest, download_type: 'initializer', chmod_mode: 'a+x')
      end

      # download any data
      dataset.data_files.each do |data_file|
        basename = data_file.filename.base + data_file.filename.extension_with_delimiter
        dest = @prob_data_path + basename
        url = Rails.configuration.worker[:hosts][:web]+worker_get_attachment_path(data_file.id)
        download_from_web(url, dest, download_type: 'data_file')
      end
    end

    # download any testcases
    if type == :testcases
      dataset.testcases.each do |tc|
        prepare_testcase_directory(nil, tc) # prepare only problem testcase path, not sub's testcase path

        # download testcase
        url_inp = Rails.configuration.worker[:hosts][:web]+worker_get_attachment_path(tc.inp_file.id)
        url_ans = Rails.configuration.worker[:hosts][:web]+worker_get_attachment_path(tc.ans_file.id)
        download_from_web(url_inp, @input_file, download_type: 'input file')
        download_from_web(url_ans, @ans_file, download_type: 'answer file')

        # do the symlink
        # testcase codename inside prob_id/testcase_id
        FileUtils.touch(@prob_testcase_path + tc.get_name_for_dir)

        # dataset_id/testcase_codename (symlink to prob_id/testcase_id)
        ds_ts_codename_dir = @ds_path + tc.get_name_for_dir
        ds_codename_dir = @problem_path + ('dsname_'+tc.dataset.get_name_for_dir)
        FileUtils.symlink(@prob_testcase_path, ds_ts_codename_dir) unless File.exist? ds_ts_codename_dir.cleanpath
        FileUtils.symlink(@ds_path, ds_codename_dir) unless File.exist? ds_codename_dir.cleanpath

        judge_log("Testcase #{tc.id} (#{tc.code_name}) downloaded")
      end
    end
  end

  # *type* is either
  #   :all where everything is downloaded and initialized
  #   :managers_only where only managers, initializers  and checker are downloaded (this is for compile job and score job only)
  def prepare_worker_dataset(dataset, type)
    prepare_dataset_directory(dataset)

    # we always prepare manager
    WorkerDataset.transaction do
      wp = WorkerDataset.lock("FOR UPDATE").find_or_create_by(worker_id: @worker_id, dataset_id: dataset.id)
      if wp.managers_status == 'created'
        # no one is working on this worker problem, I will download
        wp.update(managers_status: :downloading)

        download_dataset(dataset, :managers)

        wp.update(managers_status: :ready)
      elsif wp.managers_status == 'ready'
        judge_log("Found downloaded managers on this worker")
      else
        # status should be ready, if it stuck at :downloading, the program will stuck
      end
    end

    # we only download testcase and initialize it only when type is :all
    if type == :all
      WorkerDataset.transaction do
        wp = WorkerDataset.lock("FOR UPDATE").find_or_create_by(worker_id: @worker_id, dataset_id: dataset.id)
        if wp.testcases_status == 'created'
          # no one is working on this worker problem, I will download
          wp.update(testcases_status: :downloading)

          download_dataset(dataset, :testcases)

          # run the initializer
          unless dataset.initializer_filename.blank?
            run_initializer(dataset)
            judge_log("Testcase initialized on this worker")
          end

          wp.update(testcases_status: :ready)
        elsif wp.testcases_status == 'ready'
          judge_log("Found downloaded dataset on this worker")
        else
          # status should be ready, if it stuck at :downloading, the program will stuck
        end
      end
    end
  end

  def run_initializer(dataset)
    # build all testcases files into a json
    tc_hash = {testcases: Hash.new { |h, k| h[k] = {} } }
    dataset.testcases.each do |tc|
      prepare_testcase_directory(nil, tc)
      tc_hash[:testcases][tc.id][:inp_file] = @input_file
      tc_hash[:testcases][tc.id][:ans_file] = @ans_file
    end

    # argv form: system(*argv) bypasses the shell, so no quoting/escaping is
    # needed. The previous single-string `system(init_cmd.join ' ')` used
    # String#dump — Ruby-source escaping, NOT shell escaping — to "quote" three
    # of the four args (and left @prob_init_file unquoted), which breaks on any
    # space / $ / backtick in a path. Nothing here is student-controlled, but
    # argv is the robust form regardless.
    init_cmd = [@prob_init_file.to_s,
                tc_hash.to_json,
                @prob_config_file.to_s,
                @prob_init_work_path.to_s,
               ]
    judge_log "init file = #{@prob_init_file}"
    judge_log "init command = #{init_cmd.join ' '}"
    timeout = worker_limit(:initializer_timeout, INITIALIZER_TIMEOUT)
    out, err, status, timed_out = run_bounded(init_cmd, timeout: timeout)
    judge_log "init finished: #{status}#{' (timed out)' if timed_out}\n-- stdout --\n#{out}-- stderr --\n#{err}"
    # Raised inside prepare_worker_dataset's WorkerDataset transaction, so the
    # rollback returns testcases_status to 'created' and the next job on this
    # worker downloads and initializes the dataset again.
    raise GraderError.new("dataset initializer timed out after #{timeout} s", submission_id: @sub&.id) if timed_out
  end

  # Run argv (no shell) and give up after `timeout` seconds of wall clock.
  # The command gets its own process group, so on expiry the KILL reaches
  # whatever it forked too (a shell-script checker, psql under an
  # initializer). Open3.capture3 and system have no bound: a checker stuck in
  # a loop held its grader, and the job, forever. Returns
  # [out, err, status, timed_out]; timed_out is also true when the command
  # exited but something it forked kept the output pipes open past the bound.
  def run_bounded(cmd, timeout:)
    Open3.popen3(*cmd, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      readers = [stdout, stderr].map { |io| Thread.new { io.read } }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      left = -> { [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max }
      finished = wait_thr.join(left.call) && readers.all? { |t| t.join(left.call) }
      unless finished
        begin
          Process.kill('KILL', -wait_thr.pid)
        rescue Errno::ESRCH
          # the group is already gone
        end
        wait_thr.join
        # a process that left the group (setsid) can still hold a pipe open
        readers.each { |t| t.join(1) }
      end
      out, err = readers.map do |t|
        next t.value unless t.alive?
        t.kill
        ''
      end
      [out, err, wait_thr.value, !finished]
    end
  end

  def worker_limit(key, default)
    Rails.configuration.worker.dig(:limits, key) || default
  end

  # True when a rejudge has started a newer job chain for @sub since this
  # job's chain began (Job.chain_current?); the caller then returns
  # superseded_result before writing anything. chain_id nil skips the check:
  # engine:smoke, replay and tests drive the engine without jobs.
  def superseded?(chain_id)
    return false if chain_id.nil? || Job.chain_current?(@sub.id, chain_id)
    judge_log "#{rb_sub(@sub)} superseded by a newer grading (chain #{chain_id}); nothing written"
    true
  end

  def superseded_result
    EngineResponse::Result.failure(error: Job::SUPERSEDED_RESULT)
  end

  # set up directory and path/filename of the testcase directory
  def prepare_testcase_directory(sub, testcase)
    # preparing pathname for problem directory
    @prob_testcase_path = @problem_path + testcase.id.to_s
    @input_path = @prob_testcase_path + 'input' # we need additional dir because we will mount this dir to the isolate
    @input_file = @input_path + INPUT_FILENAME
    @ans_file = @prob_testcase_path + AnsFilename

    @prob_testcase_path.mkpath
    @input_path.mkpath

    # preparing pathname for submission directory
    if sub
      @sub_testcase_path = @submission_path + testcase.get_name_for_dir
      @output_path = @sub_testcase_path + 'output'
      @output_file = @output_path + STDOUT_FILENAME

      @sub_testcase_path.mkpath
      @output_path.mkpath
      @output_path.chmod(0777)
      # Create-only: never delete here. This helper is shared, and Checker#process
      # re-runs it after the evaluator has written stdout.txt (rev 2045 put an
      # rm_f here and took every deployed grader down on 2026-08-30). Clearing a
      # stale output is Evaluator#clear_stale_output's job, right before the run.
    end
  end

  def judge_log(msg, severity = Logger::INFO)
    JudgeLogger.logger.add(severity, msg, judge_log_tag)
  end

  def judge_log_tag
    "Worker: #{@worker_id}, Box: #{@box_id} (#{self.class.name})"
  end

  def test_log(keyword)
    n = 1_000_000
    n.times do |i|
      judge_log "#{keyword} test " + i.to_s
    end
  end

  # -------------- coloring with rainbow ----------------
  def rb_sub(sub)
    Rainbow('#'+sub.id.to_s).color(COLOR_SUB)
  end

  def rb_prob(prob)
    Rainbow(prob.id).color(COLOR_PROB)
  end

  def rb_testcase(testcase)
    Rainbow(testcase.id).color(COLOR_TESTCASE)
  end
end
