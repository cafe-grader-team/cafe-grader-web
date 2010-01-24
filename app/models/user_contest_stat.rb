class UserContestStat < ActiveRecord::Base

  belongs_to :user

  def self.update_user_start_time(user)
    stat = user.contest_stat
    if stat == nil
      stat = UserContestStat.new(:user => user,
                                 :started_at => Time.now.gmtime)
      stat.save
    end
  end

end
