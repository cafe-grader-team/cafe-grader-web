class CreateTestcases < ActiveRecord::Migration
  def change
    create_table :testcases do |t|
      t.references :problem
      t.integer :num
      t.integer :group
      t.integer :score
      t.text :input
      t.text :sol

      t.timestamps
    end
    add_index :testcases, :problem_id
  end
end
