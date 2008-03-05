class Task < ActiveRecord::Base

  STATUS_GRADING = 0
  STATUS_INQUEUE = 1
  STATUS_COMPLETE = 2

  def status_inqueue
    self.status = Task::STATUS_INQUEUE
  end

  def status_inqueue!
    status_inqueue
    self.save
  end

  def status_grading
    self.status = Task::STATUS_GRADING
  end

  def status_grading!
    status_grading
    self.save
  end

  def status_complete
    self.status = Task::STATUS_COMPLETE
  end

  def status_complete!
    status_complete
    self.save
  end

  def status_str
    case self.status
    when Task::STATUS_INQUEUE
      "inqueue"
    when Task::STATUS_GRADING
      "grading"
    when Task::STATUS_COMPLETE
      "complete"
    end
  end

  def self.get_inqueue_and_change_status(status)
    task = nil
    begin
      Task.transaction do
        task = Task.find(:first, 
                         :order => "created_at", 
                         :conditions => {:status=> Task::STATUS_INQUEUE}, 
                         :lock => true)
        if task!=nil
          task.status = status
          task.save!
        end
      end
      
    rescue
      task = nil
      
    end
    task
  end

end
