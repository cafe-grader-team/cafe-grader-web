class AddHeartBeatFull < ActiveRecord::Migration
  def up
    GraderConfiguration.create key: 'right.heartbeat_response_full', value_type: 'string', value:'RESTART', description:'Heart beat response text when user got full score (set this value to the empty string to disable this feature)'
  end

  def down

  end
end
