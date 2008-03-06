#
# A TestRequest is a composition of submission with user's testdata.
#
# Note about TestRequest#problem: Usually, A TestRequest has to be
#   associated with a problem, so that execution environment can be
#   determined.  However, to be more flexible, we have to ensure that
#   it works as well with problem=nil.  In this case, we shall provide
#   a "default" execution environment for it.  This can be done
#   seamlessly by using TestRequest#problem_name or
#   TestRequest#name_of(problem) when retrieving the name of the
#   problem: #name_of would return problem.name when problem!=nil and
#   it would return "default" when problem=nil, #problem_name just
#   call #name_of.
#

require 'fileutils'

class TestRequest < Task

  set_table_name "test_requests"

  belongs_to :user
  belongs_to :problem
  belongs_to :submission

  def self.get_inqueue_and_change_status(status)
    # since there will be only one grader grading TestRequest
    # we do not need locking (hopefully)
    
    task = Task.find(:first, 
                     :order => "created_at", 
                     :conditions => {:status=> Task::STATUS_INQUEUE})
    if task!=nil
      task.status = status
      task.save!
    end
    
    task
  end

  # interfacing with form
  def self.new_from_form_params(user,params)
    test_request = TestRequest.new
    test_request.user = user
    problem = Problem.find(params[:problem_id])
    test_request.problem = problem
    test_request.submission = 
      Submission.find_by_user_problem_number(user.id,
                                             problem.id,
                                             params[:submission_number])
    test_request.input_file_name = save_input_file(params[:input_file], user, problem)
    test_request.submitted_at = Time.new
    test_request.status_inqueue
    test_request
  end

  def problem_name
    TestRequest.name_of(self.problem)
  end

  protected

  def self.name_of(problem)
    if problem!=nil
      problem.name
    else
      "default"
    end
  end

  def self.input_file_name(user,problem)
    problem_name = TestRequest.name_of(problem)
    begin
      tmpname = TEST_REQUEST_INPUT_FILE_DIR + "/#{user.login}/#{problem_name}/#{rand(10000)}"
    end while File.exists?(tmpname)
    tmpname
  end

  def self.save_input_file(tempfile, user, problem)
    new_file_name = input_file_name(user,problem)
    dirname = File.dirname(new_file_name)
    FileUtils.mkdir_p(File.dirname(new_file_name)) if !File.exists?(dirname)
    if tempfile.instance_of?(Tempfile)
      tempfile.close
      FileUtils.move(tempfile.path,new_file_name)
    else      
      File.open(new_file_name, "wb") do |f| 
        f.write(tempfile.read) 
      end
    end
    new_file_name
  end
end
