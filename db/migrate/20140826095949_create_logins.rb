class CreateLogins < ActiveRecord::Migration[4.2]
  def change
    create_table :logins, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.string :user_id
      t.string :ip_address

      t.timestamps
    end
  end
end
