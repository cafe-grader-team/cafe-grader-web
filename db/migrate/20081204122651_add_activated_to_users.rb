class AddActivatedToUsers < ActiveRecord::Migration
  def self.up
    add_column :users, :activated, :boolean, :default => 0

    User.find(:all).each do |user|
      user.activated = true
      user.save
    end
  end


  def self.down
    remove_column :users, :activated
  end
end
