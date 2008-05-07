class Site < ActiveRecord::Base

  belongs_to :country
  has_many :users

  def clear_start_time_if_not_started
    if !self.started
      self.start_time = nil
    end
  end

  def finished?
    if !self.started
      return false
    end

    contest_time = Configuration['contest.time_limit']
    if tmatch = /(\d+):(\d+)/.match(contest_time)
      h = tmatch[1].to_i
      m = tmatch[2].to_i
      return Time.now.gmtime > (self.start_time + h.hour + m.minute)
    else
      false
    end
  end

end
