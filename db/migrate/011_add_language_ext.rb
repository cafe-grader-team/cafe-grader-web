class AddLanguageExt < ActiveRecord::Migration[4.2]
  def self.up
    add_column :languages, :ext, :string, :limit => 10

    Language.reset_column_information
    langs = Language.all
    langs.each do |l|
      l.ext = l.name
      l.save
    end
  end

  def self.down
    remove_column :languages, :ext
  end
end
