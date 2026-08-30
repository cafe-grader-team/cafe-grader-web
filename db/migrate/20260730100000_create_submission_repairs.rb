class CreateSubmissionRepairs < ActiveRecord::Migration[8.0]
  def change
    create_table :submission_repairs, charset: 'utf8mb4', collation: 'utf8mb4_0900_ai_ci' do |t|
      t.integer :original_submission_id, null: false
      t.integer :repaired_submission_id
      t.integer :status, limit: 1, null: false, default: 0
      t.text :patch, size: :medium
      t.integer :changed_lines
      t.integer :changed_chars
      t.integer :budget_lines, null: false
      t.integer :budget_chars, null: false
      t.integer :rounds_used, null: false, default: 0
      t.text :rounds_log
      t.string :fix_category
      t.string :llm_model
      t.integer :token_count_in
      t.integer :token_count_out
      t.float :cost, default: 0.0
      t.text :llm_response, size: :medium
      t.text :remark
      t.string :run_label
      t.timestamps
    end
    add_index :submission_repairs, :original_submission_id
    add_index :submission_repairs, :repaired_submission_id
    add_index :submission_repairs, :run_label
    add_index :submission_repairs, [:original_submission_id, :run_label], name: 'idx_sub_repairs_on_original_and_run'
  end
end
