class CreateSites < ActiveRecord::Migration[4.2]
  def self.up
    create_table :sites, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.string :name
      t.boolean :started
      t.datetime :start_time

      t.timestamps
    end
  end

  def self.down
    drop_table :sites
  end
end
