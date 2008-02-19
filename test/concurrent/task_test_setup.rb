ENV["RAILS_ENV"] = "test"
require File.expand_path(File.dirname(__FILE__) + "/../../config/environment")

def clear_all_tasks
  Task.find(:all).each do |task|
    task.destroy
  end
end


clear_all_tasks

(1..1000).each do |i|
  Task.create(:id => i, 
              :submission_id => i, 
              :status => Task::STATUS_INQUEUE)
end

