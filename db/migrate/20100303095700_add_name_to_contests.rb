class AddNameToContests < ActiveRecord::Migration[4.2]
  def self.up
    add_column :contests, :name, :string
  end    

  def self.down
    remove_column :contests, :name
  end
end
