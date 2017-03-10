class AddIndexToTask < ActiveRecord::Migration
  def change
    add_index :tasks, :submission_id
  end
end
