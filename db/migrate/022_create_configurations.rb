class CreateConfigurations < ActiveRecord::Migration
  def self.up
    create_table :configurations do |t|
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
