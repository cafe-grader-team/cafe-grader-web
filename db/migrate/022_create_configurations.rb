class CreateConfigurations < ActiveRecord::Migration[4.2]
  def self.up
    create_table :configurations, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column :key, :string
      t.column :value_type, :string
      t.column :value, :string
      t.timestamps
    end
  end

  def self.down
    drop_table :configurations
  end
end
