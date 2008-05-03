class CreateCountries < ActiveRecord::Migration
  def self.up
    create_table :countries do |t|
      t.column :name, :string
      t.timestamps
    end
  end

  def self.down
    drop_table :countries
  end
end
