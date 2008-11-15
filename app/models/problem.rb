class Problem < ActiveRecord::Base

  belongs_to :description

  def self.find_available_problems
    find(:all, :conditions => {:available => true}, :order => "date_added DESC")
  end

end
