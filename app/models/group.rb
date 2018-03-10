class Group < ActiveRecord::Base
  has_many :groups_problems, class_name: GroupProblem
  has_many :problems, :through => :groups_problems

  has_many :groups_users, class_name: GroupUser
  has_many :users, :through => :groups_users

  #has_and_belongs_to_many :problems
  #has_and_belongs_to_many :users


end

