ENV["RAILS_ENV"] = "test"
require File.expand_path(File.dirname(__FILE__) + "/../../config/environment")

def clear_all_tasks
  Task.all.each do |task|
    task.destroy
  end
end

puts Task.where(status: Task::STATUS_COMPLETE).length

clear_all_tasks

