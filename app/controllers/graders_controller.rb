class GradersController < ApplicationController

  before_filter :admin_authorization, except: [ :submission ]
  before_filter(only: [:submission]) {
    #check if authenticated
    return false unless authenticate

    #admin always has privileged
    if @current_user.admin?
      return true
    end

    if GraderConfiguration["right.user_view_submission"] and Submission.find(params[:id]).problem.available?
      return true
    else
      unauthorized_redirect
      return false
    end
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
    @grader_refresh_processes_amount = `ps aux | grep grader-refresh.sh | grep -v grep | wc -l`.to_i
    @grader_processes = GraderProcess.find_running_graders
    @stalled_processes = GraderProcess.find_stalled_process

    @terminated_processes = GraderProcess.find_terminated_graders
    GraderProcess.find_running_graders.each do |proc|
      lc = `ps aux | grep "cafe_grader" | grep "grader grading queue" | grep #{proc.pid} | wc -l`.to_i
      if lc < 1
        #throw "Process #{proc.pid} which has #{lc-1} instances should have been killed already!"
        flash[:notice] << '[DEBUG] Destroying #{proc.pid}'
        proc.destroy
      end
    end
    @grader_processes = GraderProcess.find_running_graders
    @last_task = Task.last
    @last_test_request = TestRequest.last
    @submission = Submission.order("id desc").limit(20)
    @backlog_submission = Submission.where('graded_at is null')
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
    GraderProcess.all.each do |p|
      `kill #{p.pid}`
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
    #@grader_pidlist = `ps aux | grep cafe_grader | grep "grader grading queue" | grep -v grep | awk '{print $2}'`.split("\n")
    #@grader_pidlist.each do |p|
    #  `kill #{p}`
    #end
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

  def manual_mode
    @grader_refresh_pidlist = `ps aux | grep grader-refresh.sh | grep -v grep | awk '{print $2}'`.split("\n")
    @grader_refresh_pidlist.each do |p|
      `kill #{p}`
    end
    flash[:notice] = 'Switched to Manual Mode.'
    redirect_to :action => 'list'
  end

  def auto_mode
    @grader_refresh_process = fork do
      exec "/bin/bash #{GRADER_ROOT_DIR}/scripts/grader-refresh.sh"
    end
    Process.detach(@grader_refresh_process)
    flash[:notice] = 'Switched to Automatically Managed Mode.'
    redirect_to :action => 'list'
  end

end
