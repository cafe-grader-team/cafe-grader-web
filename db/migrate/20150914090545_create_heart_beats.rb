class CreateHeartBeats < ActiveRecord::Migration
  def change
    create_table :heart_beats do |t|
      t.column 'user_id',:integer
      t.column 'ip_address',:string

      t.timestamps
    end
  end
end
