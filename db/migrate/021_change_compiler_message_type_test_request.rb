class ChangeCompilerMessageTypeTestRequest < ActiveRecord::Migration[4.2]
  def self.up
    change_column :test_requests, :compiler_message, :text
  end

  def self.down
    change_column :test_requests, :compiler_message, :string
  end
end
