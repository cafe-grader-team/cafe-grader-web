class AddLevelToProblems < ActiveRecord::Migration
  def self.up
    add_column :problems, :level, :integer, :default => 0
  end

  def self.down
    remove_column :problems, :level, :integer
  end
end
