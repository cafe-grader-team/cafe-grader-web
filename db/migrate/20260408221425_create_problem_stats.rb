class CreateProblemStats < ActiveRecord::Migration[8.0]
  def change
    create_table :problem_stats do |t|
      t.integer :problem_id, null: false
      t.index :problem_id, unique: true
      t.foreign_key :problems
      t.integer :sub_count, default: 0, null: false
      t.integer :solved_count, default: 0, null: false
      t.integer :attempted_count, default: 0, null: false
      t.timestamps
    end
  end
end
