class AddTerminatedToGraderProcesses < ActiveRecord::Migration
  def self.up
    add_column :grader_processes, :terminated, :boolean
  end

  def self.down
    remove_column :grader_processes, :terminated
  end
end
