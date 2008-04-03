class AddRunstatColumnsToTestRequest < ActiveRecord::Migration
  def self.up
    add_column :test_requests, :running_time, :time
    add_column :test_requests, :exit_status, :string
    add_column :test_requests, :memory_usage, :integer
  end

  def self.down
    remove_column :test_requests, :running_time
    remove_column :test_requests, :exit_status
    remove_column :test_requests, :memory_usage
  end
end
