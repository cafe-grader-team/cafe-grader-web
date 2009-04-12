class Site < ActiveRecord::Base

  belongs_to :country
  has_many :users

  def clear_start_time_if_not_started
    if !self.started
      self.start_time = nil
    end
  end

  def time_left
    contest_time = Configuration['contest.time_limit']
    if tmatch = /(\d+):(\d+)/.match(contest_time)
      h = tmatch[1].to_i
      m = tmatch[2].to_i
      
      contest_time = h.hour + m.minute

      return contest_time if !self.started

      current_time = Time.now.gmtime
      if self.start_time!=nil
        finish_time = self.start_time + contest_time
      else
        finish_time = current_time + contest_time
      end

      if current_time > finish_time
        return current_time - current_time
      else
        finish_time - current_time 
      end
    else
      nil
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
