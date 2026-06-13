class AddTitleToAnnouncements < ActiveRecord::Migration[4.2]
  def self.up
    add_column :announcements, :title, :string
  end

  def self.down
    remove_column :announcements, :title
  end
end
