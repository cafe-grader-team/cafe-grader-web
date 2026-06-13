class CreateCountries < ActiveRecord::Migration[4.2]
  def self.up
    create_table :countries, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column :name, :string
      t.timestamps
    end
  end

  def self.down
    drop_table :countries
  end
end
