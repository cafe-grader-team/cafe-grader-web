class AddFrontpageFlagToAnnouncement < ActiveRecord::Migration
  def self.up
    add_column :announcements, "frontpage", :boolean, :default => 0
  end

  def self.down
    remove_column :announcements, "frontpage"
  end
end
