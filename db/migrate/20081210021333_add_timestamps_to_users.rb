class AddTimestampsToUsers < ActiveRecord::Migration[4.2]
  def self.up
    add_timestamps :users
  end

  def self.down
    remove_timestamps :users
  end
end
