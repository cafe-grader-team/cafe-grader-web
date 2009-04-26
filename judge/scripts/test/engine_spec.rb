require File.join(File.dirname(__FILE__),'spec_helper')
require File.join(File.dirname(__FILE__),'engine_spec_helper')

describe "A grader engine, when grading submissions" do

  include GraderEngineHelperMethods

  before(:each) do
    @config = Grader::Configuration.get_instance

    # this test is from Pong
    @problem_test_normal = stub(Problem,
                                :id => 1, :name => 'test_normal', 
                                :full_score => 135)
    @user_user1 = stub(User,
                       :id => 1, :login => 'user1')
    
    @engine = Grader::Engine.new    
    init_sandbox
  end

  it "should grade normal submission" do
    grader_should(:grade => "test1_correct.c",
                  :on => @problem_test_normal,
                  :and_report => {
                    :score => 135,
                    :comment => /^(\[|P|\])+/})
  end
  

  it "should produce error message when submission cannot compile" do
    grader_should(:grade => "test1_compile_error.c",
                  :on => @problem_test_normal,
                  :and_report => {
                    :score => 0,
                    :comment => 'compilation error',
                    :compiler_message => /[Ee]rror/})
  end

  it "should produce timeout error when submission runs forever" do
    @problem_test_timeout = stub(Problem,
                                 :id => 1, :name => 'test_timeout', 
                                 :full_score => 10)
    grader_should(:grade => "test2_timeout.c",
                  :on => @problem_test_timeout,
                  :and_report => {
                    :score => 0,
                    :comment => 'TT'})
  end

  it "should produce timeout error correctly with fractional running time and fractional time limits" do
     @problem_test_timeout = stub(Problem,
                                 :id => 1, :name => 'test_timeout', 
                                 :full_score => 20)
    grader_should(:grade => "test2_05sec.c",
                  :on => @problem_test_timeout,
                  :and_report => {
                    :score => 10,
                    :comment => 'TP'})
  end
  
  it "should produce runtime error when submission uses too much static memory" do
    @problem_test_memory = stub(Problem,
                                :id => 1, :name => 'test_memory', 
                                :full_score => 20)
    grader_should(:grade => "add_too_much_memory_static.c",
                  :on => @problem_test_memory,
                  :and_report => {
                    :score => 10,
                    :comment => /[^P]P/})
  end

  it "should not allow submission to allocate too much dynamic memory" do
    @problem_test_memory = stub(Problem,
                                :id => 1, :name => 'test_memory', 
                                :full_score => 20)
    grader_should(:grade => "add_too_much_memory_dynamic.c",
                  :on => @problem_test_memory,
                  :and_report => {
                    :score => 10,
                    :comment => /[^P]P/})
  end

  it "should score test runs correctly when submission fails in some test case" do
    grader_should(:grade => "add_fail_test_case_1.c",
                  :on => @problem_test_normal,
                  :and_report => {
                    :score => 105,
                    :comment => /^.*(-|x).*$/})
  end

  it "should fail submission with non-zero exit status" do
    grader_should(:grade => "add_nonzero_exit_status.c",
                  :on => @problem_test_normal,
                  :and_report => {
                    :score => 0,
                    :comment => /^(\[|x|\])+$/})
  end

  it "should not allow malicious submission to see PROBLEM_HOME" do
    problem_test_yesno =  stub(Problem,
                                :id => 1, :name => 'test_yesno', 
                                :full_score => 10)
    grader_should(:grade => "yesno_access_problem_home.c",
                  :on => problem_test_yesno,
                  :and_report => {
                    :score => 0,
                    :comment => /(-|x)/})
  end

  it "should not allow malicious submission to open files" do
    problem_test_yesno =  stub(Problem,
                                :id => 1, :name => 'test_yesno', 
                                :full_score => 10)
    grader_should(:grade => "yesno_open_file.c",
                  :on => problem_test_yesno,
                  :and_report => {
                    :score => 0,
                    :comment => /(-|x)/})
  end

  def grader_should(args)
    @user1 = stub(User,
                  :id => 1, :login => 'user1')
    submission = 
      create_submission_from_file(1, @user1, args[:on], args[:grade])
    submission.should_receive(:graded_at=)

    expected_score = args[:and_report][:score]
    expected_comment = args[:and_report][:comment]
    if args[:and_report][:compiler_message]!=nil
      expected_compiler_message = args[:and_report][:compiler_message]
    else
      expected_compiler_message = ''
    end

    submission.should_receive(:points=).with(expected_score)
    submission.should_receive(:grader_comment=).with(expected_comment)
    submission.should_receive(:compiler_message=).with(expected_compiler_message)
    submission.should_receive(:save)

    @engine.grade(submission)
  end

  protected

  def create_normal_submission_mock_from_file(source_fname)
    create_submission_from_file(1, @user_user1, @problem_test_normal, source_fname)
  end
  
end

describe "A grader engine, when grading test requests" do

  include GraderEngineHelperMethods

  before(:each) do
    @config = Grader::Configuration.get_instance
    @engine = Grader::Engine.new(Grader::TestRequestRoomMaker.new,
                                 Grader::TestRequestReporter.new)
    init_sandbox
  end

  it "should report error if there is no problem template" do
    problem = stub(Problem,
                   :id => 1, :name => 'nothing')
    grader_should(:grade => 'test1_correct.c',
                  :on => problem,
                  :with => 'in1.txt',
                  :and_report => {
                    :graded_at= => nil,
                    :compiler_message= => '',
                    :grader_comment= => '',
                    :running_stat= => /template not found/,
                    :running_time= => nil,
                    :exit_status= => nil,
                    :memory_usage= => nil,
                    :save => nil})
  end

  it "should run test request and produce output file" do
    problem = stub(Problem,
                   :id => 1, :name => 'test_normal')
    grader_should(:grade => 'test1_correct.c',
                  :on => problem,
                  :with => 'in1.txt',
                  :and_report => {
                    :graded_at= => nil,
                    :compiler_message= => '',
                    :grader_comment= => '',
                    :running_stat= => /0.0\d* sec./, 
                    :output_file_name= => lambda { |fname|
                      File.exists?(fname).should be_true
                    },
                    :running_time= => nil,
                    :exit_status= => nil,
                    :memory_usage= => nil,
                    :save => nil})
  end

  it "should clean up problem directory after running test request" do
    problem = stub(Problem,
                   :id => 1, :name => 'test_normal')
    grader_should(:grade => 'test1_correct.c',
                  :on => problem,
                  :with => 'in1.txt',
                  :and_report => {
                    :graded_at= => nil,
                    :compiler_message= => '',
                    :grader_comment= => '',
                    :running_stat= => nil, 
                    :output_file_name= => nil,
                    :running_time= => nil,
                    :exit_status= => nil,
                    :memory_usage= => nil,
                    :save => nil})
    File.exists?(@config.user_result_dir + "/test_request/test_normal/test_cases/1/input-1.txt").should be_false
  end

  it "should compile test request with error and report compilation error" do
    problem = stub(Problem,
                   :id => 1, :name => 'test_normal')
    grader_should(:grade => 'test1_compile_error.c',
                  :on => problem,
                  :with => 'in1.txt',
                  :and_report => {
                    :graded_at= => nil,
                    :compiler_message= => /.+/,
                    :grader_comment= => /[Cc]ompil.*error/,
                    :running_stat= => '', 
                    :save => nil})
  end

  it "should report exit status" do
    problem = stub(Problem,
                   :id => 1, :name => 'test_normal')
    grader_should(:grade => 'add_nonzero_exit_status.c',
                  :on => problem,
                  :with => 'in1.txt',
                  :and_report => {
                    :graded_at= => nil,
                    :compiler_message= => '',
                    :grader_comment= => '',
                    :running_stat= => /[Ee]xit.*status.*10.*0\.0\d* sec/m,
                    :output_file_name= => lambda { |fname|
                      File.exists?(fname).should be_true
                    },
                    :running_time= => nil,
                    :exit_status= => /10/,
                    :memory_usage= => nil,
                    :save => nil})
  end

  it "should produce running statistics for normal submission" do
    problem = stub(Problem,
                   :id => 1, :name => 'test_normal')
    grader_should(:grade => 'test_run_stat.c',
                  :on => problem,
                  :with => 'in1.txt',
                  :and_report => {
                    :graded_at= => nil,
                    :compiler_message= => '',
                    :grader_comment= => '',
                    :running_stat= => nil,
                    :output_file_name= => lambda { |fname|
                      File.exists?(fname).should be_true
                    },
                    :running_time= => lambda { |t|
                      (t>=0.14) and (t<=0.16)
                    },
                    :exit_status= => nil,
                    :memory_usage= => lambda { |s|
                      (s>=500) and (s<=1000)
                    },
                    :save => nil})
  end

  protected
  def grader_should(args)
    @user1 = stub(User,
                  :id => 1, :login => 'user1')

    problem = args[:on]
    input_file = @config.test_request_input_base_dir + "/" + args[:with]

    submission = 
      create_submission_from_file(1, @user1, args[:on], args[:grade])

    test_request = stub(TestRequest,
                        :id => 1,
                        :user => @user1,
                        :problem => problem,
                        :submission => submission,
                        :input_file_name => input_file,
                        :language => submission.language,
                        :problem_name => problem.name)

    expectations = args[:and_report]

    expectations.each do |key,val|
      if val==nil
        test_request.should_receive(key)
      elsif val.class == Proc
        test_request.should_receive(key) { |fname|
          val.call(fname)
        }
      else
        test_request.should_receive(key).with(val)
      end
    end

    @engine.grade(test_request)
  end

end

