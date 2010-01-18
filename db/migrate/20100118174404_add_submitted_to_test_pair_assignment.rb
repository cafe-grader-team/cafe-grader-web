class AddSubmittedToTestPairAssignment < ActiveRecord::Migration
  def self.up
    add_column 'test_pair_assignments', 'submitted', :boolean
  end

  def self.down
    remove_column 'test_pair_assignments', 'submitted'
  end
end
