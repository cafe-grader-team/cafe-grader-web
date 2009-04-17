class AddCommonExtToLanguages < ActiveRecord::Migration
  def self.up
    # language.common_ext is a comma-separated list of common file
    # extensions.
    add_column :languages, :common_ext, :string

    # updating table information
    Language.reset_column_information
    common_ext = { 
      'c' => 'c',
      'cpp' => 'cpp,cc',
      'pas' => 'pas' 
    }
    Language.find(:all).each do |lang|
      lang.common_ext = common_ext[lang.name]
      lang.save
    end
  end

  def self.down
    remove_column :languages, :common_ext
  end
end
