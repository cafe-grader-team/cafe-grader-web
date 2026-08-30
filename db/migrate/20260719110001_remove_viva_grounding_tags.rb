class RemoveVivaGroundingTags < ActiveRecord::Migration[8.0]
  def up
    # Tag#problems_tags has no `dependent: :destroy` (and the FK is RESTRICT,
    # not CASCADE), so a tag with problem associations would fail `tag.destroy`
    # on the problems_tags FK. Clear the join rows explicitly first; attachment
    # purge still happens via Tag's has_many_attached :files destroy callback.
    Tag.where(kind: 3).find_each do |tag|
      tag.problems_tags.destroy_all
      tag.destroy
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
