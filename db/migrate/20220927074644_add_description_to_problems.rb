class AddDescriptionToProblems < ActiveRecord::Migration[7.0]
  def change
    add_column :problems, :description, :text
    add_column :problems, :markdown, :boolean
  end
end
