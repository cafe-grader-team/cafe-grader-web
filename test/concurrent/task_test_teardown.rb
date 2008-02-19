ENV["RAILS_ENV"] = "test"
require File.expand_path(File.dirname(__FILE__) + "/../../config/environment")

def clear_all_tasks
  Task.find(:all).each do |task|
    task.destroy
  end
end

puts Task.find(:all,
               :conditions => {:status => Task::STATUS_COMPLETE}).length

clear_all_tasks

