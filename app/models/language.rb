class Language < ApplicationRecord
  has_many :submissions

  # `name` is the canonical identifier used by the engine (see Compiler.get_compiler,
  # JudgeBase#isolate_*_by_lang). It must be unique and immutable once set.
  validates :name, presence: true, uniqueness: true
  validate :name_immutable, on: :update

  @@languages_by_ext = {}

  def default_submission_filename
    "submission." + (self.ext || '')
  end

  def self.seed
    Language.find_or_create_by!( name: 'c').update!(pretty_name: 'C', ext: 'c', common_ext: 'c' )
    Language.find_or_create_by!( name: 'cpp').update!(pretty_name: 'C++', ext: 'cpp', common_ext: 'cpp,cc' )
    Language.find_or_create_by!( name: 'pas').update!(pretty_name: 'Pascal', ext: 'pas', common_ext: 'pas' )
    Language.find_or_create_by!( name: 'ruby').update!(pretty_name: 'Ruby', ext: 'rb', common_ext: 'rb' )
    Language.find_or_create_by!( name: 'python').update!(pretty_name: 'Python', ext: 'py', common_ext: 'py' )
    Language.find_or_create_by!( name: 'java').update!(pretty_name: 'Java', ext: 'java', common_ext: 'java' )
    Language.find_or_create_by!( name: 'php').update!(pretty_name: 'PHP', ext: 'php', common_ext: 'php' )
    Language.find_or_create_by!( name: 'haskell').update!(pretty_name: 'Haskell', ext: 'hs', common_ext: 'hs' )
    Language.find_or_create_by!( name: 'digital').update!(pretty_name: 'Digital', ext: 'dig', common_ext: 'dig' )
    Language.find_or_create_by!( name: 'rust').update!(pretty_name: 'Rust', ext: 'rs', common_ext: 'rs' )
    Language.find_or_create_by!( name: 'go').update!(pretty_name: 'Go', ext: 'go', common_ext: 'go' )
    Language.find_or_create_by!( name: 'postgres').update!(pretty_name: 'PostgreSQL', ext: 'sql', common_ext: 'sql' )
    Language.find_or_create_by!( name: 'archive').update!(pretty_name: 'Archive', ext: 'zip', common_ext: 'zip,jar', binary: true )
    Language.find_or_create_by!( name: 'text').update!(pretty_name: 'Text', ext: 'txt', common_ext: 'txt' )
    Language.find_or_create_by!( name: 'viva').update!(pretty_name: 'Viva Exam', ext: nil, common_ext: nil, binary: false )
  end

  def self.cache_ext_hash
    @@languages_by_ext = {}
    Language.all.each do |language|
      next if language.common_ext.blank?
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

  private

  def name_immutable
    errors.add(:name, 'cannot be changed once the language is created') if name_changed?
  end
end
