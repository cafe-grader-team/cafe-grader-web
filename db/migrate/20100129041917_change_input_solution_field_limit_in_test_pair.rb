class ChangeInputSolutionFieldLimitInTestPair < ActiveRecord::Migration
  def self.up
    change_column :test_pairs, :input, :text, :limit => 1.megabytes
    change_column :test_pairs, :solution, :text, :limit => 1.megabytes
  end

  def self.down
    change_column :test_pairs, :input, :text
    change_column :test_pairs, :solution, :text
  end
end
