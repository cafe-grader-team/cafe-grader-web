class AddUrlToProblem < ActiveRecord::Migration
  def self.up
    add_column :problems, :url, :string
  end

  def self.down
    remove_column :problems, :url
  end
end
