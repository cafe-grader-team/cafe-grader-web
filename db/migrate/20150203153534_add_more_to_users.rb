class AddMoreToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :enabled, :boolean, default: 1
    add_column :users, :remark, :string
  end
end
