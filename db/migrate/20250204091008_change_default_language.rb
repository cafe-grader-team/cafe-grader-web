class ChangeDefaultLanguage < ActiveRecord::Migration[7.0]
  def change
    rename_column :users, :default_language, :default_language_id
  end
end
