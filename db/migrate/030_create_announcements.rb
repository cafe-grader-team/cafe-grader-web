class CreateAnnouncements < ActiveRecord::Migration
  def self.up
    create_table :announcements do |t|
      t.string :author
      t.text :body
      t.boolean :published

      t.timestamps
    end
  end

  def self.down
    drop_table :announcements
  end
end
