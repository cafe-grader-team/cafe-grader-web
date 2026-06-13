class AddIndexToTaskStatus < ActiveRecord::Migration[5.2]
  def change
    add_index :tasks, :status
  end
end
