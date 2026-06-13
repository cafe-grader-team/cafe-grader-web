class CreateTestcases < ActiveRecord::Migration[4.2]
  def change
    create_table :testcases, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
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
