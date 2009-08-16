class AddTitleToAnnouncements < ActiveRecord::Migration
  def self.up
    add_column :announcements, :title, :string
  end

  def self.down
    remove_column :announcements, :title
  end
end
