class CreateUserContestStats < ActiveRecord::Migration
  def self.up
    create_table :user_contest_stats do |t|
      t.integer :user_id
      t.timestamp :started_at

      t.timestamps
    end
  end

  def self.down
    drop_table :user_contest_stats
  end
end
