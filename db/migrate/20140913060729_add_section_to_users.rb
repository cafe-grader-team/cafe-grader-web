class AddSectionToUsers < ActiveRecord::Migration
  def change
    add_column :users, :section, :string
  end
end
