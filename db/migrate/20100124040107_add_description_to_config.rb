class AddDescriptionToConfig < ActiveRecord::Migration
  def self.up
    add_column :configurations, :description, :text
  end

  def self.down
    remove_column :configurations, :description
  end
end
