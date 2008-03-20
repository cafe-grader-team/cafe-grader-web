class AddTaskToGraderProcess < ActiveRecord::Migration
  def self.up
    add_column :grader_processes, :task_id, :integer
  end

  def self.down
    remove_column :grader_processes, :task_id
  end
end
