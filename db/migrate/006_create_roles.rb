class CreateRoles < ActiveRecord::Migration[4.2]
  def self.up
    create_table :roles, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column 'name', :string
    end

    create_table :roles_users, :id => false, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column 'role_id', :integer
      t.column 'user_id', :integer
    end

    add_index :roles_users, :user_id
  end

  def self.down
    drop_table :roles_users
    drop_table :roles
  end
end
