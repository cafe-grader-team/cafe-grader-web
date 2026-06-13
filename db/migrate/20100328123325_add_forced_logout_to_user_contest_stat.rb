class AddForcedLogoutToUserContestStat < ActiveRecord::Migration[4.2]
  def self.up
    add_column :user_contest_stats, :forced_logout, :boolean
  end

  def self.down
    remove_column :user_contest_stats, :forced_logout, :boolean
  end
end
