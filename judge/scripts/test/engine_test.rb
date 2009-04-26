require 'test/unit'
require 'rubygems'
require 'mocha'

require File.join(File.dirname(__FILE__),'test_helper')

class GraderEngineTest < UnitTest.TestCase

  def setup
    @@lang_c = stub(:name => 'c', :ext => 'c')
    @@lang_cpp = stub(:name => 'cpp', :ext => 'cpp')
    @@lang_pas = stub(:name => 'pas', :ext => 'pas')

    @config = Grader::Configuration.get_instance

    @problem_test1 = stub(:id => 1, :name => 'test1', :full_score => 135)
    @user_user1 = stub(:id => 1, :login => 'user1')

    @engine = Grader::Engine.new    

    init_sandbox
  end

  def teardown
  end

  def test_grade_oldest_task_with_no_submission
    Task.expects(:get_inqueue_and_change_status).returns(nil)
    assert_equal nil, @engine.grade_oldest_task, 'should return nil when there is no task'
  end

  def test_normal_submission
    submission = create_test1_submission_mock_from_file("test1_correct.c")

    submission.expects(:graded_at=)
    submission.expects(:points=).with(135)
    submission.expects(:grader_comment=).with do |value|
      /^PASSED/.match(value)
    end
    submission.expects(:compiler_message=).with('')
    submission.expects(:save)

    @engine.grade(submission)
  end

  def test_compile_error_submission
    submission = create_test1_submission_mock_from_file("test1_compile_error.c")

    submission.expects(:graded_at=)
    submission.expects(:points=).with(0)
    submission.expects(:grader_comment=).with('FAILED: compile error')
    submission.expects(:compiler_message=) do |value|
      /[Ee]rror/.match value
    end
    submission.expects(:save)

    @engine.grade(submission)
  end

  def test_timeout_submission
    @problem_test2 = stub(:id => 1, :name => 'test2', :full_score => 10)
    @user_user1 = stub(:id => 1, :login => 'user1')

    submission = create_submission_from_file(1, @user_user1, @problem_test2,
                                             "test2_timeout.c")

    submission.expects(:graded_at=)
    submission.expects(:points=).with(0)
    submission.expects(:grader_comment=).with do |value|
      /^FAILED: TT$/.match value
    end
    submission.expects(:compiler_message=).with('')
    submission.expects(:save)

    @engine.grade(submission)
  end

  def test_timeout_submission_running_one_and_a_half_second
    @problem_test2 = stub(:id => 1, :name => 'test2', :full_score => 20)
    @user_user1 = stub(:id => 1, :login => 'user1')

    submission = create_submission_from_file(1, @user_user1, @problem_test2,
                                             "test2_1-5sec.c")

    submission.expects(:graded_at=)
    submission.expects(:points=).with(10)
    submission.expects(:grader_comment=).with do |value|
      /^FAILED: TP$/.match value
    end
    submission.expects(:compiler_message=).with('')
    submission.expects(:save)

    @engine.grade(submission)
  end

  def test_grade_oldest_task
    # mock submission
    submission = create_test1_submission_mock_from_file("test1_correct.c")

    submission.expects(:graded_at=)
    submission.expects(:points=).with(135)
    submission.expects(:grader_comment=).with do |value|
      /^PASSED/.match(value)
    end
    submission.expects(:compiler_message=).with('')
    submission.expects(:save)

    # mock task
    task = stub(:id => 1, :submission_id => submission.id)
    Task.expects(:get_inqueue_and_change_status).returns(task)
    task.expects(:status_complete!)

    # mock Submission
    Submission.expects(:find).with(task.submission_id).returns(submission)

    @engine.grade_oldest_task
  end

  def test_grade_oldest_task_with_grader_process
    grader_process = stub
    grader_process.expects(:report_active)

    @engine = Grader::Engine.new(grader_process)

    test_grade_oldest_task
  end

  protected

  def clear_sandbox
    clear_cmd = "rm -rf #{@config.test_sandbox_dir}/*"
    system(clear_cmd)
  end

  def init_sandbox
    clear_sandbox
    Dir.mkdir @config.user_result_dir
    cp_cmd = "cp -R #{@config.test_data_dir}/ev #{@config.test_sandbox_dir}"
    system(cp_cmd)
  end

  def create_submission_from_file(id, user, problem, source_fname, language = @@lang_c)
    source = File.open(@config.test_data_dir + "/" + source_fname).read
    stub(:id => id, :user => user, :problem => problem,
         :source => source, :language => language)
  end

  def create_test1_submission_mock_from_file(source_fname)
    create_submission_from_file(1, @user_user1, @problem_test1, source_fname)
  end
  
end
