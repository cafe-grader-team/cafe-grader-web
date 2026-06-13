class AddIndexToLogin < ActiveRecord::Migration[5.2]
  def change
    add_index :logins, :user_id
  end
end
