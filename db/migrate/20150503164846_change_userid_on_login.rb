class ChangeUseridOnLogin < ActiveRecord::Migration[4.2]
  def up
    change_column :logins, :user_id, :integer
  end

  def down
    change_column :logins, :user_id, :string
  end
end
