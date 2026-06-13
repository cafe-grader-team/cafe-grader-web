class AddLastHeartbeatToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :last_heartbeat, :datetime
    add_column :tags, :color, :string
  end
end
