class Language < ActiveRecord::Base

  @@languages_by_ext = {}

  def self.cache_ext_hash
    @@languages_by_ext = {}
    Language.all.each do |language|
      language.common_ext.split(',').each do |ext|
        @@languages_by_ext[ext] = language
      end
    end
  end

  def self.find_by_extension(ext)
    if @@languages_by_ext.length == 0
      Language.cache_ext_hash
    end
    if @@languages_by_ext.has_key? ext
      return @@languages_by_ext[ext]
    else
      return nil
    end
  end
end
