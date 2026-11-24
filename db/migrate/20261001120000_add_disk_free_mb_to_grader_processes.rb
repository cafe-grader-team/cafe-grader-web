# Issue #25: a judge host reports the free space of its judge directories in
# the grader heartbeat (Grader#main_loop); the graders page warns when any
# host, the web host included, runs low (GraderProcess::LOW_DISK_MB).
class AddDiskFreeMbToGraderProcesses < ActiveRecord::Migration[8.0]
  def change
    add_column :grader_processes, :disk_free_mb, :integer
  end
end
