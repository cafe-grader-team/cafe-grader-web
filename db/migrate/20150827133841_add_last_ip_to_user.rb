class AddLastIpToUser < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :last_ip, :string
  end
end
