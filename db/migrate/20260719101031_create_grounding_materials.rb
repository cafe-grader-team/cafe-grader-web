class CreateGroundingMaterials < ActiveRecord::Migration[8.0]
  def change
    create_table :grounding_materials do |t|
      t.string  :title, null: false
      t.text    :description
      t.text    :body, size: :medium
      t.integer :estimated_tokens, null: false, default: 0
      t.timestamps
    end

    create_join_table :grounding_materials, :problems do |t|
      t.index [:grounding_material_id, :problem_id],
              unique: true, name: 'idx_gm_problems_unique'
      t.index :problem_id
    end
  end
end
