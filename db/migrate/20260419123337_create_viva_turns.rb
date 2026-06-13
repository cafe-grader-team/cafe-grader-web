class CreateVivaTurns < ActiveRecord::Migration[8.0]
  def change
    create_table :viva_turns, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci' do |t|
      t.integer :submission_id, null: false
      t.integer :sequence, null: false
      t.integer :role, null: false, default: 2
      t.integer :status, null: false, default: 0
      t.text :content, limit: 16.megabytes - 1
      t.text :llm_response_raw, limit: 16.megabytes - 1
      t.string :llm_model
      t.float :cost
      t.integer :token_count_in
      t.integer :token_count_out
      t.timestamps
    end

    add_index :viva_turns, [:submission_id, :sequence], unique: true
    add_foreign_key :viva_turns, :submissions
  end
end
