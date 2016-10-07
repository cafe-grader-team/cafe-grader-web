class UpdateHeartBeat < ActiveRecord::Migration
  def up
    GraderConfiguration.create key: 'right.heartbeat_response', value_type: 'string', value:'OK', description:'Heart beat response text'
    add_index :heart_beats, :updated_at
  end

  def down
    remove_index :heart_beats, :updated_at
  end
end
