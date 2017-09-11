class Group < ActiveRecord::Base
  has_and_belongs_to_many :problems
  has_and_belongs_to_many :users
end

