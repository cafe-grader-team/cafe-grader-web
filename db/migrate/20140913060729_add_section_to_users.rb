class AddSectionToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :section, :string
  end
end
