class AddTaskTypeToGraderProcesses < ActiveRecord::Migration
  def self.up
    add_column 'grader_processes', 'task_type', :string
  end

  def self.down
    remove_column 'grader_processes', 'task_type'
  end
end
