class CreateUsers < ActiveRecord::Migration[4.2]
  def self.up
    create_table :users, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column :login, :string, :limit => 10
      t.column :full_name, :string
      t.column :hashed_password, :string
      t.column :salt, :string, :limit => 5
      t.column :alias, :string
    end
    # force unique name
    add_index :users, :login, :unique => true
  end

  def self.down
    drop_table :users
  end
end
