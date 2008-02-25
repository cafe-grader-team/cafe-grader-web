class GraderProcess < ActiveRecord::Base
  
  belongs_to :task

  def self.find_by_host_and_pid(host,pid)
    return GraderProcess.find(:first, 
                              :conditions => { 
                                :host => host, 
                                :pid => pid
                              })
  end
  
  def self.register(host,pid,mode)
    grader = GraderProcess.find_by_host_and_pid(host,pid)
    if grader
      grader.mode = mode
      grader.active = nil
      grader.task_id = nil
      grader.save
    else
      grader = GraderProcess.create(:host => host, 
                                    :pid => pid, 
                                    :mode => mode)
    end
    grader
  end

  def self.find_stalled_process()
    GraderProcess.find(:all,
                       :conditions => ["active AND updated_at < ?",
                                       Time.now.gmtime - GraderProcess.stalled_time])
  end
  
  def report_active(task=nil)
    self.active = true
    self.task = task
    self.save
  end                

  def report_inactive()
    self.active = false
    self.task = nil
    self.save
  end                

  protected

  def self.stalled_time()
    return 1.minute
  end

end
