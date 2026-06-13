class AddTerminatedToGraderProcesses < ActiveRecord::Migration[4.2]
  def self.up
    add_column :grader_processes, :terminated, :boolean
  end

  def self.down
    remove_column :grader_processes, :terminated
  end
end
