class AddLanguageExt < ActiveRecord::Migration
  def self.up
    add_column :languages, :ext, :string, :limit => 10
    
    langs = Language.find(:all)
    langs.each do |l|
      l.ext = l.name
      l.save
    end
  end

  def self.down
    remove_column :languages, :ext
  end
end
