class CreateLogins < ActiveRecord::Migration
  def change
    create_table :logins do |t|
      t.string :user_id
      t.string :ip_address

      t.timestamps
    end
  end
end
