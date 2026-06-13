class CreateUserContestStats < ActiveRecord::Migration[4.2]
  def self.up
    create_table :user_contest_stats, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.integer :user_id
      t.timestamp :started_at

      t.timestamps
    end
  end

  def self.down
    drop_table :user_contest_stats
  end
end
