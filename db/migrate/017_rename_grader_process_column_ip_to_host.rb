class RenameGraderProcessColumnIpToHost < ActiveRecord::Migration
  def self.up
    rename_column :grader_processes, :ip, :host
  end

  def self.down
    rename_column :grader_processes, :host, :ip
  end
end
