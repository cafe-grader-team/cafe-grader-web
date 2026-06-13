class AddContestFlagToAnnouncements < ActiveRecord::Migration[4.2]
  def self.up
    add_column :announcements, :contest_only, :boolean, :default => false
  end

  def self.down
    remove_column :announcements, :contest_only
  end
end
