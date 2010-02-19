class AddDescriptionFilenameToProblems < ActiveRecord::Migration
  def self.up
    add_column :problems, :description_filename, :string
  end

  def self.down
    remove_column :problems, :description_filename
  end
end
