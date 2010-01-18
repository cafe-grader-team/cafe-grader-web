class AddNumberToTestPair < ActiveRecord::Migration
  def self.up
    add_column 'test_pairs', 'number', :integer
  end

  def self.down
    remove_column 'test_pairs', 'number'
  end
end
