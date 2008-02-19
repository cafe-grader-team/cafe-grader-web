require File.dirname(__FILE__) + '/../test_helper'

class TaskTest < Test::Unit::TestCase
  fixtures :tasks

  self.use_transactional_fixtures = false

  def test_get_inqueue_simple
    task1 = Task.get_inqueue_and_change_status(Task::STATUS_GRADING)    
    
    assert_equal task1.id, 3, "should get the earliest task"
    assert_equal task1.status, Task::STATUS_GRADING, "status changes"
    
    task2 = Task.get_inqueue_and_change_status(Task::STATUS_GRADING)    
    
    assert_equal task2.id, 4, "should get the next task"
    assert_equal task2.status, Task::STATUS_GRADING, "status changes"
  end
  
  def generate_tasks(n)
    n.times do |i|
      Task.create(:submission_id => i, 
                  :status => Task::STATUS_INQUEUE,
                  :create_at => Time.now + i.minutes)
    end
  end
  
  # use the process version in /test/concurrent instead
  def UNUSED_test_get_inqueue_concurrent
    ActiveRecord::Base.allow_concurrency = true

    task1 = Task.get_inqueue_and_change_status(Task::STATUS_GRADING)    

    assert_equal task1.id, 3, "should get the earliest task"
    assert_equal task1.status, Task::STATUS_GRADING, "status changes"

    ActiveRecord::Base.verify_active_connections!
  end

end

