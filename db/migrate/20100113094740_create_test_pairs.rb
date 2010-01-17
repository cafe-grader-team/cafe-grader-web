class CreateTestPairs < ActiveRecord::Migration
  def self.up
    create_table :test_pairs do |t|
      t.integer :problem_id
      t.text :input
      t.text :solution

      t.timestamps
    end
  end

  def self.down
    drop_table :test_pairs
  end
end
