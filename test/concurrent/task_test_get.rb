ENV["RAILS_ENV"] = "test"
require File.expand_path(File.dirname(__FILE__) + "/../../config/environment")

def take_wait_return
  task = Task.get_inqueue_and_change_status(Task::STATUS_GRADING)
  sleep (rand)/10.0
  task.status_complete
  task.save!
end

n = 300

n.times do |i|
  take_wait_return
  puts i
end
