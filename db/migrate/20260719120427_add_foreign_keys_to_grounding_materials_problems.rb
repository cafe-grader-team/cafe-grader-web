class AddForeignKeysToGroundingMaterialsProblems < ActiveRecord::Migration[8.0]
  def up
    change_column :grounding_materials_problems, :problem_id, :integer, null: false
    add_foreign_key :grounding_materials_problems, :problems
    add_foreign_key :grounding_materials_problems, :grounding_materials
  end

  def down
    remove_foreign_key :grounding_materials_problems, :grounding_materials
    remove_foreign_key :grounding_materials_problems, :problems
    change_column :grounding_materials_problems, :problem_id, :bigint, null: false
  end
end
