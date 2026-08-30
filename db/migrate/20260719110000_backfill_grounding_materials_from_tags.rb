class BackfillGroundingMaterialsFromTags < ActiveRecord::Migration[8.0]
  # Copy viva_grounding tags → GroundingMaterial. Non-destructive: original
  # tags and their attachments stay until the next migration.
  def up
    viva_grounding_kind = 3 # Tag.kinds[:viva_grounding] at time of writing
    Tag.where(kind: viva_grounding_kind).find_each do |tag|
      # No skip-guard: back up EVERY viva_grounding tag unconditionally. A title
      # guard would silently skip a tag whose name collides with an existing
      # GroundingMaterial (tags.name is not unique; admins can create materials
      # via the UI), and the cleanup migration would then destroy that tag —
      # silent data loss. Unconditional create makes the blanket cleanup safe;
      # the worst case is a visible duplicate on a rare partial-failure re-run.
      gm = GroundingMaterial.create!(
        title:       tag.name,
        description: tag.description,
        body:        tag.params
      )
      tag.files.blobs.each { |blob| gm.files.attach(blob) } # share blobs, non-destructive
      gm.problems << tag.problems.to_a
      gm.reload
      gm.update_column(:estimated_tokens, gm.compute_estimated_tokens)
    end
  end

  def down
    # Best-effort: remove materials that mirror a still-present viva_grounding tag.
    GroundingMaterial.where(title: Tag.where(kind: 3).pluck(:name)).destroy_all
  end
end
