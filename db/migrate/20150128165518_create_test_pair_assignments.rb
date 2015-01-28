class CreateTestPairAssignments < ActiveRecord::Migration
  def up
    create_table :test_pair_assignments do |t|
      t.integer "user_id"
      t.integer "problem_id"
      t.integer "test_pair_id"
      t.integer "request_number"
      t.boolean "submitted"
      t.timestamps
    end
  end

  def down
    drop_table :test_pair_assignments
  end
end
