class AddStatusToHeartBeat < ActiveRecord::Migration
  def change
    add_column :heart_beats, :status, :string
  end
end
