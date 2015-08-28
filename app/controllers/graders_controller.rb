class GradersController < ApplicationController

  before_filter :admin_authorization, except: [ :submission ]
  before_filter(only: [:submission]) {
    return false unless authenticate

    if GraderConfiguration["right.user_view_submission"]
      return true;
    end

    admin_authorization
  }

  verify :method => :post, :only => ['clear_all', 
                                     'start_exam',
                                     'start_grading',
                                     'stop_all', 
                                     'clear_terminated'], 
         :redirect_to => {:action => 'index'}

  def index
    redirect_to :action => 'list'
  end

  def list
    @grader_processes = GraderProcess.find_running_graders
    @stalled_processes = GraderProcess.find_stalled_process

    @terminated_processes = GraderProcess.find_terminated_graders
    
    @last_task = Task.find(:first,
                           :order => 'created_at DESC')
    @last_test_request = TestRequest.find(:first,
                                          :order => 'created_at DESC')
    @submission = Submission.order("id desc").limit(20)
  end

  def clear
    grader_proc = GraderProcess.find(params[:id])
    grader_proc.destroy if grader_proc!=nil
    redirect_to :action => 'list'
  end

  def clear_terminated
    GraderProcess.find_terminated_graders.each do |p|
      p.destroy
    end
    redirect_to :action => 'list'
  end

  def clear_all
    GraderProcess.find(:all).each do |p|
      p.destroy
    end
    redirect_to :action => 'list'
  end

  def view
    if params[:type]=='Task'
      redirect_to :action => 'task', :id => params[:id]
    else
      redirect_to :action => 'test_request', :id => params[:id]
    end
  end

  def test_request
    @test_request = TestRequest.find(params[:id])
  end

  def task
    @task = Task.find(params[:id])
  end

  def submission
    @submission = Submission.find(params[:id])
    formatter = Rouge::Formatters::HTML.new(css_class: 'highlight', line_numbers: true )
    lexer = case @submission.language.name
      when "c"      then Rouge::Lexers::C.new
      when "cpp"    then Rouge::Lexers::Cpp.new
      when "pas"    then Rouge::Lexers::Pas.new
      when "ruby"   then Rouge::Lexers::Ruby.new
      when "python" then Rouge::Lexers::Python.new
      when "java"   then Rouge::Lexers::Java.new
      when "php"    then Rouge::Lexers::PHP.new
    end
    @formatted_code = formatter.format(lexer.lex(@submission.source))
    @css_style = Rouge::Themes::ThankfulEyes.render(scope: '.highlight')

    user = User.find(session[:user_id])
    SubmissionViewLog.create(user_id: session[:user_id],submission_id: @submission.id) unless user.admin?

  end

  # various grader controls

  def stop 
    grader_proc = GraderProcess.find(params[:id])
    GraderScript.stop_grader(grader_proc.pid)
    flash[:notice] = 'Grader stopped.  It may not disappear now, but it should disappear shortly.'
    redirect_to :action => 'list'
  end

  def stop_all
    GraderScript.stop_graders(GraderProcess.find_running_graders + 
                              GraderProcess.find_stalled_process)
    flash[:notice] = 'Graders stopped.  They may not disappear now, but they should disappear shortly.'
    redirect_to :action => 'list'
  end

  def start_grading
    GraderScript.start_grader('grading')
    flash[:notice] = '2 graders in grading env started, one for grading queue tasks, another for grading test request'
    redirect_to :action => 'list'
  end

  def start_exam
    GraderScript.start_grader('exam')
    flash[:notice] = '2 graders in grading env started, one for grading queue tasks, another for grading test request'
    redirect_to :action => 'list'
  end

end
