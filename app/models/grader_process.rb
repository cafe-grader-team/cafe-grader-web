class GraderProcess < ActiveRecord::Base
  
  def self.find_by_ip_and_pid(ip,pid)
    return GraderProcess.find(:first, 
                              :conditions => { 
                                :ip => ip, 
                                :pid => pid
                              })
  end

  def self.report_active(ip,pid,mode)
  end                

  def self.report_inactive(ip,pid,mode)
  end                

end
