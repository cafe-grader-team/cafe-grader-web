class AddMoreToUsers < ActiveRecord::Migration
  def change
    add_column :users, :enabled, :boolean, default: 1
    add_column :users, :remark, :string
  end
end
