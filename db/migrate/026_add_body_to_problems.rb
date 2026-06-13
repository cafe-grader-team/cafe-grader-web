class AddBodyToProblems < ActiveRecord::Migration[4.2]
  def self.up
    add_column :problems, :body, :text
  end

  def self.down
    remove_column :problems, :body
  end
end
