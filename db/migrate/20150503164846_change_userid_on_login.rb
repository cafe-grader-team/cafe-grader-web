class ChangeUseridOnLogin < ActiveRecord::Migration
  def up
    change_column :logins, :user_id, :integer
  end

  def down
    change_column :logins, :user_id, :string
  end
end
