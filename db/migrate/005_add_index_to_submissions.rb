class AddIndexToSubmissions < ActiveRecord::Migration
  def self.up
    add_index :submissions, [:user_id, :problem_id]
  end

  def self.down
    remove_index :submissions, :column => [:user_id, :problem_id]
  end
end
