class AddSupportsForOutputOnlyProblems < ActiveRecord::Migration
  def self.up
    add_column :submissions, :source_filename, :string
    add_column :problems, :output_only, :boolean
  end

  def self.down
    remove_column :submissions, :source_filename
    add_column :problems, :output_only, :boolean
  end
end
