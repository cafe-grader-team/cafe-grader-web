class AddTaskTypeToGraderProcesses < ActiveRecord::Migration[4.2]
  def self.up
    add_column 'grader_processes', 'task_type', :string
  end

  def self.down
    remove_column 'grader_processes', 'task_type'
  end
end
