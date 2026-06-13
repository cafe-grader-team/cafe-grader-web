class AddEnabledToGroup < ActiveRecord::Migration[5.2]
  def change
    add_column :groups, :enabled, :boolean, default: true
  end
end
