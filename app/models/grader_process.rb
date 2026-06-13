class GraderProcess < ApplicationRecord

  enum :status, {idle: 0, working: 1}

  def job_type_array
    return Job.job_types.keys if job_type.blank?
    return job_type.split
  end

  def self.lock_for_fetching_submission(host_id,sub_id)
    GraderProcess.lock("FOR UPDATE").where(host_id: host_id, fetching_sub_id: sub_id)
  end

  # this is for 2023 new grader
  def self.register_grader(host_id,box_id)
    gp = GraderProcess.find_or_create_by(host_id: host_id, box_id: box_id)
    gp.update(pid: Process.pid)
    return gp
  end

  protected

  def self.stalled_time()
    return 1.minute
  end


end
