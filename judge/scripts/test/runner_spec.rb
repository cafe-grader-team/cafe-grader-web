require File.join(File.dirname(__FILE__),'spec_helper')
require File.join(File.dirname(__FILE__),'engine_spec_helper')

describe "A grader runner, when grade task" do

  include GraderEngineHelperMethods

  before(:each) do
    @config = Grader::Configuration.get_instance
    @problem_test_normal = stub(Problem,
                                :id => 1, :name => 'test_normal', 
                                :full_score => 135)
    @user_user1 = stub(User,
                       :id => 1, :login => 'user1')
    
    @engine = Grader::Engine.new    
    @runner = Grader::Runner.new(@engine)
    init_sandbox
  end

  it "should just return nil when there is no submission" do
    Task.should_receive(:get_inqueue_and_change_status).and_return(nil)
    @runner.grade_oldest_task.should be_nil
  end

  it "should grade oldest task in queue" do
    submission = create_normal_submission_mock_from_file("test1_correct.c")

    submission.should_receive(:graded_at=)
    submission.should_receive(:points=).with(135)
    submission.should_receive(:grader_comment=).with(/^PASSED/)
    submission.should_receive(:compiler_message=).with('')
    submission.should_receive(:save)

    # mock task
    task = stub(Task,:id => 1, :submission_id => submission.id)
    Task.should_receive(:get_inqueue_and_change_status).and_return(task)
    task.should_receive(:status_complete!)

    # mock Submission
    Submission.should_receive(:find).
      with(task.submission_id).
      and_return(submission)

    @runner.grade_oldest_task
  end

  # to be converted
  def test_grade_oldest_task_with_grader_process
    grader_process = stub
    grader_process.expects(:report_active)

    @runner = Grader::Runner.new(@engine,grader_process)

    test_grade_oldest_task
  end

  protected

  def create_normal_submission_mock_from_file(source_fname)
    create_submission_from_file(1, @user_user1, @problem_test_normal, source_fname)
  end
  
end

