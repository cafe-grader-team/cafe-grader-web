class MainController < ApplicationController

  before_filter :authenticate, :except => [:index, :login]
  before_filter :check_viewability, :except => [:index, :login]

  append_before_filter :update_user_start_time, :except => [:index, :login]

  # to prevent log in box to be shown when user logged out of the
  # system only in some tab
  prepend_before_filter :reject_announcement_refresh_when_logged_out, :only => [:announcements]

  # COMMENTED OUT: filter in each action instead
  # before_filter :verify_time_limit, :only => [:submit]

  verify :method => :post, :only => [:submit],
         :redirect_to => { :action => :index }

  # COMMENT OUT: only need when having high load
  # caches_action :index, :login

  # NOTE: This method is not actually needed, 'config/routes.rb' has
  # assigned action login as a default action.
  def index
    redirect_to :action => 'login'
  end

  def login
    saved_notice = flash[:notice]
    reset_session
    flash.now[:notice] = saved_notice

    # EXPERIMENT:
    # Hide login if in single user mode and the url does not
    # explicitly specify /login
    #
    # logger.info "PATH: #{request.path}"
    # if Configuration['system.single_user_mode'] and 
    #     request.path!='/main/login'
    #   @hidelogin = true
    # end

    @announcements = Announcement.find_for_frontpage
    render :action => 'login', :layout => 'empty'
  end

  def list
    prepare_list_information
  end

  def help
    @user = User.find(session[:user_id])
  end

  def submit
    user = User.find(session[:user_id])

    @submission = Submission.new(params[:submission])
    @submission.user = user
    @submission.language_id = 0
    if (params['file']) and (params['file']!='')
      @submission.source = params['file'].read 
      @submission.source_filename = params['file'].original_filename
    end
    @submission.submitted_at = Time.new.gmtime

    if Configuration.time_limit_mode? and user.contest_finished?
      @submission.errors.add_to_base "The contest is over."
      prepare_list_information
      render :action => 'list' and return
    end

    if @submission.valid?
      if @submission.save == false
	flash[:notice] = 'Error saving your submission'
      elsif Task.create(:submission_id => @submission.id, 
                        :status => Task::STATUS_INQUEUE) == false
	flash[:notice] = 'Error adding your submission to task queue'
      end
    else
      prepare_list_information
      render :action => 'list' and return
    end
    redirect_to :action => 'list'
  end

  def source
    submission = Submission.find(params[:id])
    if submission.user_id == session[:user_id]
      send_data(submission.source, 
		{:filename => submission.download_filename, 
                  :type => 'text/plain'})
    else
      flash[:notice] = 'Error viewing source'
      redirect_to :action => 'list'
    end
  end

  def compiler_msg
    @submission = Submission.find(params[:id])
    if @submission.user_id == session[:user_id]
      render :action => 'compiler_msg', :layout => 'empty'
    else
      flash[:notice] = 'Error viewing source'
      redirect_to :action => 'list'
    end
  end

  def submission
    @user = User.find(session[:user_id])
    @problems = @user.available_problems
    if params[:id]==nil
      @problem = nil
      @submissions = nil
    else
      @problem = Problem.find_by_name(params[:id])
      if not @problem.available
        redirect_to :action => 'list'
        flash[:notice] = 'Error: submissions for that problem are not viewable.'
        return
      end
      @submissions = Submission.find_all_by_user_problem(@user.id, @problem.id)
    end
  end

  def result
    if !Configuration.show_grading_result
      redirect_to :action => 'list' and return
    end
    @user = User.find(session[:user_id])
    @submission = Submission.find(params[:id])
    if @submission.user!=@user
      flash[:notice] = 'You are not allowed to view result of other users.'
      redirect_to :action => 'list' and return
    end
    prepare_grading_result(@submission)
  end

  def load_output
    if !Configuration.show_grading_result or params[:num]==nil
      redirect_to :action => 'list' and return
    end
    @user = User.find(session[:user_id])
    @submission = Submission.find(params[:id])
    if @submission.user!=@user
      flash[:notice] = 'You are not allowed to view result of other users.'
      redirect_to :action => 'list' and return
    end
    case_num = params[:num].to_i
    out_filename = output_filename(@user.login, 
                                   @submission.problem.name,
                                   @submission.id,
                                   case_num)
    if !FileTest.exists?(out_filename)
      flash[:notice] = 'Output not found.'
      redirect_to :action => 'list' and return
    end

    if defined?(USE_APACHE_XSENDFILE) and USE_APACHE_XSENDFILE
      response.headers['Content-Type'] = "application/force-download"
      response.headers['Content-Disposition'] = "attachment; filename=\"output-#{case_num}.txt\""
      response.headers["X-Sendfile"] = out_filename
      response.headers['Content-length'] = File.size(out_filename)
      render :nothing => true
    else
      send_file out_filename, :stream => false, :filename => "output-#{case_num}.txt", :type => "text/plain"
    end
  end

  def error
    @user = User.find(session[:user_id])
  end

  # announcement refreshing and hiding methods

  def announcements
    if params.has_key? 'recent'
      prepare_announcements(params[:recent])
    else
      prepare_announcements
    end
    render(:partial => 'announcement', 
           :collection => @announcements,
           :locals => {:announcement_effect => true})
  end

  protected

  def prepare_announcements(recent=nil)
    if Configuration.show_tasks_to?(@user)
      @announcements = Announcement.find_published(true)
    else
      @announcements = Announcement.find_published
    end
    if recent!=nil
      recent_id = recent.to_i
      @announcements = @announcements.find_all { |a| a.id > recent_id }
    end
  end

  def prepare_list_information
    @user = User.find(session[:user_id])
    if not Configuration.multicontests?
      @problems = @user.available_problems
    else
      @contest_problems = @user.available_problems_group_by_contests
      @problems = @user.available_problems
    end
    @prob_submissions = {}
    @problems.each do |p|
      sub = Submission.find_last_by_user_and_problem(@user.id,p.id)
      if sub!=nil
        @prob_submissions[p.id] = { :count => sub.number, :submission => sub }
      else
        @prob_submissions[p.id] = { :count => 0, :submission => nil }
      end
    end
    prepare_announcements
  end

  def check_viewability
    @user = User.find(session[:user_id])
    if (!Configuration.show_tasks_to?(@user)) and
        ((action_name=='submission') or (action_name=='submit'))
      redirect_to :action => 'list' and return
    end
  end

  def prepare_grading_result(submission)
    if Configuration.task_grading_info.has_key? submission.problem.name
      grading_info = Configuration.task_grading_info[submission.problem.name]
    else
      # guess task info from problem.full_score
      cases = submission.problem.full_score / 10
      grading_info = {
        'testruns' => cases, 
        'testcases' => cases
      }
    end
    @test_runs = []
    if grading_info['testruns'].is_a? Integer
      trun_count = grading_info['testruns']
      trun_count.times do |i|
        @test_runs << [ read_grading_result(@user.login,
                                            submission.problem.name,
                                            submission.id,
                                            i+1) ]
      end
    else
      grading_info['testruns'].keys.sort.each do |num|
        run = []
        testrun = grading_info['testruns'][num]
        testrun.each do |c|
          run << read_grading_result(@user.login,
                                     submission.problem.name,
                                     submission.id,
                                     c)
        end
        @test_runs << run
      end
    end
  end

  def grading_result_dir(user_name, problem_name, submission_id, case_num)
    return "#{GRADING_RESULT_DIR}/#{user_name}/#{problem_name}/#{submission_id}/test-result/#{case_num}"
  end
  
  def output_filename(user_name, problem_name, submission_id, case_num)
    dir = grading_result_dir(user_name,problem_name, submission_id, case_num)
    return "#{dir}/output.txt"
  end

  def read_grading_result(user_name, problem_name, submission_id, case_num)
    dir = grading_result_dir(user_name,problem_name, submission_id, case_num)
    result_file_name = "#{dir}/result"
    if !FileTest.exists?(result_file_name)
      return {:num => case_num, :msg => 'program did not run'}
    else
      results = File.open(result_file_name).readlines
      run_stat = extract_running_stat(results)
      output_filename = "#{dir}/output.txt"
      if FileTest.exists?(output_filename)
        output_file = true
        output_size = File.size(output_filename)
      else
        output_file = false
        output_size = 0
      end

      return {
        :num => case_num,
        :msg => results[0],
        :run_stat => run_stat,
        :output => output_file,
        :output_size => output_size
      }
    end  
  end
  
  # copied from grader/script/lib/test_request_helper.rb
  def extract_running_stat(results)
    running_stat_line = results[-1]
    
    # extract exit status line
    run_stat = ""
    if !(/[Cc]orrect/.match(results[0]))
      run_stat = results[0].chomp
    else
      run_stat = 'Program exited normally'
    end
    
    logger.info "Stat line: #{running_stat_line}"

    # extract running time
    if res = /r(.*)u(.*)s/.match(running_stat_line)
      seconds = (res[1].to_f + res[2].to_f)
      time_stat = "Time used: #{seconds} sec."
    else
      seconds = nil
      time_stat = "Time used: n/a sec."
    end
    
    # extract memory usage
    if res = /s(.*)m/.match(running_stat_line)
      memory_used = res[1].to_i
    else
      memory_used = -1
    end
    
    return {
      :msg => "#{run_stat}\n#{time_stat}",
      :running_time => seconds,
      :exit_status => run_stat,
      :memory_usage => memory_used
    }
  end

  def update_user_start_time
    user = User.find(session[:user_id])
    user.update_start_time
  end

  def reject_announcement_refresh_when_logged_out
    if not session[:user_id]
      render :text => 'Access forbidden', :status => 403
    end

    if Configuration.multicontests?
      user = User.find(session[:user_id])
      if user.contest_stat.forced_logout
        render :text => 'Access forbidden', :status => 403
      end
    end
  end

end

