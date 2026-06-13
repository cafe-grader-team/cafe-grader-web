class AddEmailToUsers < ActiveRecord::Migration[4.2]
  def self.up
    add_column :users, :email, :string
  end

  def self.down
    remove_column :users, :email
  end
end
