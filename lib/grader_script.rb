module GraderScript

  def self.grader_control_enabled?
    if defined? GRADER_SCRIPT_DIR
      GRADER_SCRIPT_DIR != ''
    else
      false
    end
  end

  def self.stop_grader(pid)
    if GraderScript.grader_control_enabled?
      cmd = "#{GRADER_SCRIPT_DIR}/grader stop #{pid}"
      system(cmd)
    end
  end

  def self.stop_graders(pids)
    if GraderScript.grader_control_enabled?
      pid_str = (pids.map { |process| process.pid.to_a }).join ' '
      cmd = "#{GRADER_SCRIPT_DIR}/grader stop " + pid_str
      system(cmd)
    end
  end

  def self.start_grader(env)
    if GraderScript.grader_control_enabled?
      cmd = "#{GRADER_SCRIPT_DIR}/grader #{env} queue &"
      system(cmd)
      cmd = "#{GRADER_SCRIPT_DIR}/grader #{env} test_request &"
      system(cmd)
    end    
  end

end
