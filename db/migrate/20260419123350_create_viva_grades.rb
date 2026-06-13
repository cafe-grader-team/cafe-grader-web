class CreateVivaGrades < ActiveRecord::Migration[8.0]
  def change
    create_table :viva_grades, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci' do |t|
      t.integer :submission_id, null: false
      t.string :rubric_version
      t.text :score_json, limit: 16.megabytes - 1
      t.decimal :total_points, precision: 8, scale: 4
      t.text :narrative, limit: 16.megabytes - 1
      t.string :llm_model
      t.text :llm_response_raw, limit: 16.megabytes - 1
      t.float :cost
      t.datetime :graded_at
      t.timestamps
    end

    add_index :viva_grades, :submission_id, unique: true
    add_foreign_key :viva_grades, :submissions
  end
end
