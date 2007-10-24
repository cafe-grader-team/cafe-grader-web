class CreateUsers < ActiveRecord::Migration
  def self.up
    create_table :users do |t|
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
