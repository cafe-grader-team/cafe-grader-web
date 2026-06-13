class AddRoleToContestUser < ActiveRecord::Migration[7.0]
  def change
    add_column :contests_users, :role, :integer, default: 0
  end
end
