class AddJsonParamsToTags < ActiveRecord::Migration[8.0]
  def change
    add_column :tags, :params, :text, limit: 16.megabytes - 1
    add_column :tags, :kind, :integer, default: 0

    reversible do |dir|
      dir.up do
        Tag.where(primary: true).update_all(kind: 'topic')
      end
      dir.down do
        Tag.where(kind: :topic).update_all(primary: true)
      end
    end

    remove_column :tags, :primary, :boolean, default: 0
  end
end
