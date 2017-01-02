class GraderProcess < ActiveRecord::Base
  
  def self.find_by_host_and_pid(host,pid)
    return GraderProcess.where(host:host).where(pid: pid).first
  end
  
  def self.register(host,pid,mode)
    grader = GraderProcess.find_by_host_and_pid(host,pid)
    if grader
      grader.mode = mode
      grader.active = nil
      grader.task_id = nil
      grader.task_type = nil
      grader.terminated = false
      grader.save
    else
      grader = GraderProcess.create(:host => host, 
                                    :pid => pid, 
                                    :mode => mode,
                                    :terminated => false)
    end
    grader
  end
 
  def self.find_running_graders
    where(terminated: false)
  end

  def self.find_terminated_graders
    where(terminated: true)
  end

  def self.find_stalled_process
    where(terminated: false).where(active: true).where("updated_at < ?",Time.now.gmtime - GraderProcess.stalled_time)
  end
  
  def report_active(task=nil)
    self.active = true
    if task!=nil
      self.task_id = task.id
      self.task_type = task.class.to_s
    else
      self.task_id = nil
      self.task_type = nil
    end
    self.save
  end                

  def report_inactive(task=nil)
    self.active = false
    if task!=nil
      self.task_id = task.id
      self.task_type = task.class.to_s
    else
      self.task_id = nil
      self.task_type = nil
    end
    self.save
  end                

  def terminate
    self.terminated = true
    self.save
  end

  protected

  def self.stalled_time()
    return 1.minute
  end

end
