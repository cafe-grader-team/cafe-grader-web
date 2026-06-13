class AddStatusToTasks < ActiveRecord::Migration[4.2]
  def self.up
    add_column :tasks, :status, :integer
    add_column :tasks, :updated_at, :datetime

    Task.reset_column_information
    Task.all.each do |task|
      task.status_complete
      task.save
    end
  end

  def self.down
    remove_column :tasks, :updated_at
    remove_column :tasks, :status
  end
end
