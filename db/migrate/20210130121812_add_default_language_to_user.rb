class AddDefaultLanguageToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :default_language, :integer
  end
end
