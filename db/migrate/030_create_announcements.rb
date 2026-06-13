class CreateAnnouncements < ActiveRecord::Migration[4.2]
  def self.up
    create_table :announcements, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
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
