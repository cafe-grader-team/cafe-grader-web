class Announcement < ActiveRecord::Base

  def self.published(contest_started=false)
    if contest_started
      where(published: true).where(frontpage: false).order(created_at: :desc)
    else
      where(published: true).where(frontpage: false).where(contest_only: false).order(created_at: :desc)
    end
  end

  def self.frontpage
    where(published: 1).where(frontpage: 1).order(created_at: :desc)
  end

end
