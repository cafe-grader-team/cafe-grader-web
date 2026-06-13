class AddNotesToAnnouncements < ActiveRecord::Migration[4.2]
  def self.up
    add_column :announcements, :notes, :string
  end

  def self.down
    remove_column :announcements, :notes
  end
end
