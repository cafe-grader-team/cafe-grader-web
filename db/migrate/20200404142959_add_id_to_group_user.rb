class AddIdToGroupUser < ActiveRecord::Migration[5.2]
  def change
    add_column :groups_users, :id, :primary_key
  end
end
