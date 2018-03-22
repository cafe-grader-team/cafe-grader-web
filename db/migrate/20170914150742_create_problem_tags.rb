class CreateProblemTags < ActiveRecord::Migration
  def change
    create_table :problems_tags do |t|
      t.references :problem, index: true, foreign_key: true
      t.references :tag, index: true, foreign_key: true

      t.index [:problem_id,:tag_id], unique: true
    end
  end
end
