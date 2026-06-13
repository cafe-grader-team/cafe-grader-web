class CreateTestPairs < ActiveRecord::Migration[4.2]
  def self.up
    create_table :test_pairs, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
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
