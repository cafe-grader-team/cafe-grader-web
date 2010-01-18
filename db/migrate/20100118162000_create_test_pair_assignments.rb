class CreateTestPairAssignments < ActiveRecord::Migration
  def self.up
    create_table :test_pair_assignments do |t|
      t.integer "user_id"
      t.integer "problem_id"
      t.integer "test_pair_id"
      t.integer "test_pair_number"
      t.integer "request_number"
      t.timestamps
    end
  end

  def self.down
    drop_table :test_pair_assignments
  end
end
