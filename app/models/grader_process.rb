require 'open3'

class GraderProcess < ApplicationRecord
  enum :status, {idle: 0, working: 1}

  # ---- disk space (issue #25) ----
  # A judge host measures the free space of its judge directories once a
  # minute inside its heartbeat (Grader#main_loop) and stores the smaller
  # figure in disk_free_mb; the web host measures its own directories when
  # the graders page renders (GradersController#index). Below LOW_DISK_MB a
  # host is flagged. df(1) is used so no gem is needed on the judge hosts.
  LOW_DISK_MB = 2048

  # Free megabytes on the filesystem holding +path+; nil when the path does
  # not exist or df cannot answer, so a broken measurement never raises
  # inside the grader loop.
  def self.free_disk_mb(path)
    return nil if path.blank? || !File.exist?(path.to_s)
    out, status = Open3.capture2e('df', '-Pk', path.to_s)
    return nil unless status.success?
    fields = out.lines.last.to_s.split
    return nil unless fields.size >= 6 && fields[3].match?(/\A\d+\z/)
    fields[3].to_i / 1024
  rescue SystemCallError
    nil
  end

  # The least free space across the worker's directories (judge data and the
  # isolate box root), from config/worker.yml. nil when none can be measured.
  def self.worker_free_disk_mb(dirs = nil)
    dirs ||= Rails.configuration.worker[:directory]&.values_at(:judge_path, :isolate_working_dir)
    Array(dirs).filter_map { |d| free_disk_mb(d) }.min
  end

  # One entry per judge host: its newest row that reported a figure.
  # Returns [[host, disk_free_mb, last_heartbeat], ...] sorted by free space.
  def self.disk_by_host
    where.not(disk_free_mb: nil).where.not(host: [nil, ''])
         .order(last_heartbeat: :desc)
         .group_by(&:host)
         .map { |host, rows| [host, rows.first.disk_free_mb, rows.first.last_heartbeat] }
         .sort_by { |_, mb, _| mb }
  end

  def self.low_disk?(mb)
    mb.present? && mb < LOW_DISK_MB
  end

  def job_type_array
    return Job.job_types.keys if job_type.blank?
    return job_type.split
  end

  def self.lock_for_fetching_submission(host_id, sub_id)
    GraderProcess.lock("FOR UPDATE").where(host_id: host_id, fetching_sub_id: sub_id)
  end

  # this is for 2023 new grader
  def self.register_grader(host_id, box_id)
    gp = GraderProcess.find_or_create_by(host_id: host_id, box_id: box_id)
    gp.update(pid: Process.pid)
    return gp
  end

  protected

  def self.stalled_time
    return 1.minute
  end
end
