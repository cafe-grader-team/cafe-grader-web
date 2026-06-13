class AddJobPriority < ActiveRecord::Migration[7.0]
  def change
    add_column :jobs, :priority, :integer, default: 0
  end
end
