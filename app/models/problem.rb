class Problem < ActiveRecord::Base

  def self.find_available_problems
    find(:all, :conditions => {:available => true})
  end

end
