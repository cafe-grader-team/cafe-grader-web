class AddDescriptionToConfig < ActiveRecord::Migration[4.2]
  def self.up
    add_column :configurations, :description, :text
  end

  def self.down
    remove_column :configurations, :description
  end
end
