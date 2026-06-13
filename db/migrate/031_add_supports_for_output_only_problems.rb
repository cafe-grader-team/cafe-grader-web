class AddSupportsForOutputOnlyProblems < ActiveRecord::Migration[4.2]
  def self.up
    add_column :submissions, :source_filename, :string
    add_column :problems, :output_only, :boolean
  end

  def self.down
    remove_column :submissions, :source_filename
    remove_column :problems, :output_only
  end
end
