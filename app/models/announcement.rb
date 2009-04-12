class Announcement < ActiveRecord::Base

  def self.find_published(contest_started=false)
    if contest_started
      Announcement.find(:all,
                        :conditions => "(published = 1) AND (frontpage = 0)",
                        :order => "created_at DESC")
    else
      Announcement.find(:all,
                        :conditions => "(published = 1) AND (frontpage = 0) AND (contest_only = 0)",
                        :order => "created_at DESC")
    end
  end

  def self.find_for_frontpage
    Announcement.find(:all,
                      :conditions => "(published = 1) AND (frontpage = 1)",
                      :order => "created_at DESC")
  end

end
