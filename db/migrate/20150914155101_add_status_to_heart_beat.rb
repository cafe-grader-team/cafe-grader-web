class AddStatusToHeartBeat < ActiveRecord::Migration[4.2]
  def change
    add_column :heart_beats, :status, :string
  end
end
