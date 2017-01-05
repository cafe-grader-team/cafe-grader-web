module GraderScript

  def self.grader_control_enabled?
    if defined? GRADER_ROOT_DIR
      GRADER_ROOT_DIR != ''
    else
      false
    end
  end

  def self.raw_dir
    File.join GRADER_ROOT_DIR, "raw"
  end

  def self.call_grader(params)
    if GraderScript.grader_control_enabled?
      cmd = File.join(GRADER_ROOT_DIR, "scripts/grader") + " " + params
      system(cmd)
    end
  end

  def self.stop_grader(pid)
    GraderScript.call_grader "stop #{pid}"
  end

  def self.stop_graders(pids)
    pid_str = (pids.map { |process| process.pid.to_s }).join ' '
    GraderScript.call_grader "stop #{pid_str}"
  end

  def self.start_grader(env)
    GraderScript.call_grader "#{env} queue --err-log &"
    GraderScript.call_grader "#{env} test_request -err-log &"
  end

  def self.call_import_problem(problem_name, 
                               problem_dir,
                               time_limit=1,
                               memory_limit=32,
                               checker_name='text')
    if GraderScript.grader_control_enabled?
      cur_dir = `pwd`.chomp
      Dir.chdir(GRADER_ROOT_DIR)

      script_name = File.join(GRADER_ROOT_DIR, "scripts/import_problem")
      cmd = "#{script_name} #{problem_name} #{problem_dir} #{checker_name}" +
        " -t #{time_limit} -m #{memory_limit}"

      output = `#{cmd}`

      Dir.chdir(cur_dir)

      return "import CMD: #{cmd}\n" + output
    end
    return ''
  end

  def self.call_import_testcase(problem_name)
    if GraderScript.grader_control_enabled?
      cur_dir = `pwd`.chomp
      Dir.chdir(GRADER_ROOT_DIR)

      script_name = File.join(GRADER_ROOT_DIR, "scripts/load_testcase")
      cmd = "#{script_name} #{problem_name}"

      output = `#{cmd}`

      Dir.chdir(cur_dir)
      return "Testcase import result:\n" + output
    end
  end

end
