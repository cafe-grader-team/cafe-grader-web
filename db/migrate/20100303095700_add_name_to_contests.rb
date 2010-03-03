class AddNameToContests < ActiveRecord::Migration
  def self.up
    add_column :contests, :name, :string
  end    

  def self.down
    remove_column :contests, :name
  end
end
