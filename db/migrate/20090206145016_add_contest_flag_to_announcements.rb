class AddContestFlagToAnnouncements < ActiveRecord::Migration
  def self.up
    add_column :announcements, :contest_only, :boolean, :default => false
  end

  def self.down
    remove_column :announcements, :contest_only
  end
end
