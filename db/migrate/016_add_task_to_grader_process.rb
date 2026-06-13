class AddTaskToGraderProcess < ActiveRecord::Migration[4.2]
  def self.up
    add_column :grader_processes, :task_id, :integer
  end

  def self.down
    remove_column :grader_processes, :task_id
  end
end
