class AddTimestampsToUsers < ActiveRecord::Migration
  def self.up
    add_timestamps :users
  end

  def self.down
    remove_timestamps :users
  end
end
