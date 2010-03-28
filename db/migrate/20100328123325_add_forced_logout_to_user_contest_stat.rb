class AddForcedLogoutToUserContestStat < ActiveRecord::Migration
  def self.up
    add_column :user_contest_stats, :forced_logout, :boolean
  end

  def self.down
    remove_column :user_contest_stats, :forced_logout, :boolean
  end
end
