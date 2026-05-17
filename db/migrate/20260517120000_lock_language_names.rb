class LockLanguageNames < ActiveRecord::Migration[8.0]
  # Ensures the canonical Language rows exist (re-runs Language.seed so newly
  # added entries like `viva` land on existing installations without manually
  # running `rails db:seed`) and locks the `name` column — which the engine
  # matches as if it were an enum (Compiler.get_compiler, isolate_*_by_lang) —
  # with a uniqueness index so it can't silently drift.
  def up
    Language.reset_column_information
    Language.seed

    dupes = Language.group(:name).having('COUNT(*) > 1').count
    if dupes.any?
      raise ActiveRecord::IrreversibleMigration,
            "Refusing to add unique index — duplicate Language names: #{dupes.inspect}. " \
            "Resolve manually (merge submissions onto one row, delete the other) and re-run."
    end

    unless index_exists?(:languages, :name, unique: true)
      add_index :languages, :name, unique: true
    end
  end

  def down
    if index_exists?(:languages, :name, unique: true)
      remove_index :languages, :name
    end
  end
end
