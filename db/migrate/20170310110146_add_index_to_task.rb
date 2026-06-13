class AddIndexToTask < ActiveRecord::Migration[4.2]
  def change
    add_index :tasks, :submission_id
  end
end
