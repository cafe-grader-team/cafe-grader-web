class CreateDescriptions < ActiveRecord::Migration[4.2]
  def self.up
    create_table :descriptions, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column :body, :text
      t.column :markdowned, :boolean
      t.timestamps
    end
  end

  def self.down
    drop_table :descriptions
  end
end
