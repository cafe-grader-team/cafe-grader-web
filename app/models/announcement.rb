class Announcement < ActiveRecord::Base

  def self.find_published
    Announcement.find(:all,
                      :conditions => "(published = 1) AND (frontpage = 0)",
                      :order => "created_at DESC")
  end

  def self.find_for_frontpage
    Announcement.find(:all,
                      :conditions => "(published = 1) AND (frontpage = 1)",
                      :order => "created_at DESC")
  end

end
