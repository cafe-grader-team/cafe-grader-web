class Problem < ActiveRecord::Base

  belongs_to :description

  def self.find_available_problems
    find(:all, :conditions => {:available => true})
  end

end
