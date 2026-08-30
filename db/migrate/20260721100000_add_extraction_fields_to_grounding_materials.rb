class AddExtractionFieldsToGroundingMaterials < ActiveRecord::Migration[8.0]
  def change
    # D4 grounding extraction (docs/superpowers/specs/2026-07-20-viva-deployment-readiness-design.md):
    # a one-shot multimodal LLM pass turns the attached PDF(s) into a review-only
    # markdown draft. Deliberately a separate column from `body` — the draft must
    # never silently become the live grounding text; the author copies it in and
    # saves explicitly.
    add_column :grounding_materials, :extraction_draft, :text, size: :medium
    add_column :grounding_materials, :extraction_requested_at, :datetime
  end
end
