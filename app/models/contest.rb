class Contest < ActiveRecord::Base

  has_and_belongs_to_many :users
  has_and_belongs_to_many :problems

  scope :enabled, :conditions => {:enabled => true}

end
