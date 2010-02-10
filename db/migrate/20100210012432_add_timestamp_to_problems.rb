class AddTimestampToProblems < ActiveRecord::Migration
  def self.up
    add_column :problems, :updated_at, :timestamp
  end

  def self.down
    remove_column :problems, :updated_at
  end
end
