class CreateProblemTags < ActiveRecord::Migration[4.2]
  def change
    create_table :problems_tags, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.references :problem, index: true, foreign_key: true
      t.references :tag, index: true, foreign_key: true

      t.index [:problem_id,:tag_id], unique: true
    end
  end
end
