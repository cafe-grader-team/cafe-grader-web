class AddCodejomFieldsToUsers < ActiveRecord::Migration
  def self.up
    add_column :users, :member1_full_name, :string
    add_column :users, :member2_full_name, :string
    add_column :users, :member3_full_name, :string
    add_column :users, :high_school, :boolean
    add_column :users, :member1_school_name, :string
    add_column :users, :member2_school_name, :string
    add_column :users, :member3_school_name, :string
  end

  def self.down
    remove_column :users, :member1_full_name
    remove_column :users, :member2_full_name
    remove_column :users, :member3_full_name
    remove_column :users, :high_school
    remove_column :users, :member1_school_name
    remove_column :users, :member2_school_name
    remove_column :users, :member3_school_name
  end
end
