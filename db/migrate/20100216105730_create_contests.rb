class CreateContests < ActiveRecord::Migration[4.2]
  def self.up
    create_table :contests, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.string :title
      t.boolean :enabled

      t.timestamps
    end
  end

  def self.down
    drop_table :contests
  end
end
