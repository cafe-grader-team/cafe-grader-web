class Problem < ActiveRecord::Base

  belongs_to :description

  validates_presence_of :name
  validates_presence_of :full_name

  def self.find_available_problems
    find(:all, :conditions => {:available => true}, :order => "date_added DESC")
  end

end
