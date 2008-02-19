class AddStatusToTasks < ActiveRecord::Migration
  def self.up
    add_column :tasks, :status, :integer
    add_column :tasks, :updated_at, :datetime

    Task.reset_column_information
    Task.find(:all).each do |task|
      task.status_complete
      task.save
    end
  end

  def self.down
    remove_column :tasks, :updated_at
    remove_column :tasks, :status
  end
end
