#
# A runner drives the engine into various tasks.
# 

module Grader

  class Runner

    def initialize(engine, grader_process=nil)
      @engine = engine
      @grader_process = grader_process
    end

    def grade_oldest_task
      task = Task.get_inqueue_and_change_status(Task::STATUS_GRADING)
      if task!=nil 
        @grader_process.report_active(task) if @grader_process!=nil
        
        submission = Submission.find(task.submission_id)
        @engine.grade(submission)
        task.status_complete!
        @grader_process.report_inactive(task) if @grader_process!=nil
      end
      return task
    end

    def grade_problem(problem)
      users = User.find(:all)
      users.each do |u|
        puts "user: #{u.login}"
        last_sub = Submission.find_last_by_user_and_problem(u.id,problem.id)
        if last_sub!=nil
          @engine.grade(last_sub)
        end
      end
    end

    def grade_submission(submission)
      puts "Submission: #{submission.id} by #{submission.user.full_name}"
      @engine.grade(submission)
    end

    def grade_oldest_test_request
      test_request = TestRequest.get_inqueue_and_change_status(Task::STATUS_GRADING)
      if test_request!=nil 
        @grader_process.report_active(test_request) if @grader_process!=nil
        
        @engine.grade(test_request)
        test_request.status_complete!
        @grader_process.report_inactive(test_request) if @grader_process!=nil
      end
      return test_request
    end

  end

end

