class Site < ActiveRecord::Base

  belongs_to :country
  has_many :users

  def clear_start_time_if_not_started
    if !self.started
      self.start_time = nil
    end
  end

  def time_left
    contest_time = Configuration.contest_time_limit

    return nil if contest_time == nil

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
      return finish_time - current_time 
    end
  end

  def finished?
    if !self.started
      return false
    end

    contest_time = Configuration.contest_time_limit
    if contest_time!=nil
      return Time.now.gmtime > (self.start_time + contest_time)
    else
      false
    end
  end

end
