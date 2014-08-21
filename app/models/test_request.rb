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

  validates_presence_of :submission
  validate :must_have_valid_problem

  def problem_name
    TestRequest.name_of(self.problem)
  end

  def language
    self.submission.language
  end

  def self.get_inqueue_and_change_status(status)
    # since there will be only one grader grading TestRequest
    # we do not need locking (hopefully)
    
    test_request = TestRequest.find(:first, 
                                    :order => "created_at", 
                                    :conditions => {:status=> Task::STATUS_INQUEUE})
    if test_request!=nil
      test_request.status = status
      test_request.save!
    end
    
    test_request
  end

  # interfacing with form
  def self.new_from_form_params(user,params)
    test_request = TestRequest.new
    test_request.user = user
    begin
      problem = Problem.find(params[:problem_id])
    rescue ActiveRecord::RecordNotFound
      problem = nil
    end
    test_request.problem = problem
    if problem!=nil
      test_request.submission = 
        Submission.find_by_user_problem_number(user.id,
                                               problem.id,
                                               params[:submission_number])
    else
      test_request.submission = nil
    end

    # checks if the user submits any input file
    if params[:input_file]==nil or params[:input_file]==""
      test_request.errors.add(:base,"No input submitted.")
      test_request.input_file_name = nil
    else
      test_request.input_file_name = save_input_file(params[:input_file], user, problem)
      if test_request.input_file_name == nil
        test_request.errors.adds(:base,"No input submitted.")
      end
      if params[:additional_file]!=nil and params[:additional_file]!=""
        save_additional_file(params[:additional_file], 
                             "#{test_request.input_file_name}.files")
      end
    end
    test_request.submitted_at = Time.new.gmtime
    test_request.status_inqueue
    test_request
  end

  protected

  def self.name_of(problem)
    if problem!=nil
      problem.name
    else
      "default"
    end
  end

  def self.random_input_file_name(user,problem)
    problem_name = TestRequest.name_of(problem)
    begin
      tmpname = TEST_REQUEST_INPUT_FILE_DIR + "/#{user.login}/#{problem_name}/#{rand(10000)}"
    end while File.exists?(tmpname)
    tmpname
  end

  def self.save_input_file(tempfile, user, problem)
    new_file_name = random_input_file_name(user,problem)
    dirname = File.dirname(new_file_name)
    FileUtils.mkdir_p(File.dirname(new_file_name)) if !File.exists?(dirname)

    # when the user did not submit any file
    return nil if tempfile==""

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

  def self.save_additional_file(tempfile,dir)
    new_file_name = "#{dir}/#{tempfile.original_filename}"
    dirname = File.dirname(new_file_name)
    FileUtils.mkdir_p(File.dirname(new_file_name)) if !File.exists?(dirname)

    # when the user did not submit any file
    return nil if tempfile==""

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

  #
  # validations
  #
  def must_have_valid_problem
    if problem==nil
      errors.add('problem',"must be specified.")
    elsif (!problem.available) and (self.new_record?)
      errors.add('problem',"must be valid.")
    end
  end

end
