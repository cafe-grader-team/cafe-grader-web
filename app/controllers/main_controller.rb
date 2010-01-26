class MainController < ApplicationController

  before_filter :authenticate, :except => [:index, :login]
  before_filter :check_viewability, :except => [:index, :login]

  # COMMENTED OUT: filter in each action instead
  # before_filter :verify_time_limit, :only => [:submit]

  verify :method => :post, :only => [:submit, :download_input, :submit_solution],
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
    flash[:notice] = saved_notice

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
    @problems = Problem.find_available_problems
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

    response.headers['Content-Type'] = "application/force-download"
    response.headers['Content-Disposition'] = "attachment; filename=\"output-#{case_num}.txt\""
    response.headers["X-Sendfile"] = out_filename
    response.headers['Content-length'] = File.size(out_filename)
    render :nothing => true
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

  #
  # actions for Code Jom
  #
  def download_input
    problem = Problem.find(params[:id])
    user = User.find(session[:user_id])
    if user.can_request_new_test_pair_for? problem
      assignment = user.get_new_test_pair_assignment_for problem
      assignment.save

      send_data(assignment.test_pair.input,
                { :filename => "#{problem.name}-#{assignment.request_number}.in",
                  :type => 'text/plain' })
    else
      recent_assignment = user.get_recent_test_pair_assignment_for problem
      send_data(recent_assignment.test_pair.input,
                { :filename => "#{problem.name}-#{recent_assignment.request_number}.in",
                  :type => 'text/plain' })
    end
  end
  
  def submit_solution
    problem = Problem.find(params[:id])
    user = User.find(session[:user_id])
    recent_assignment = user.get_recent_test_pair_assignment_for problem
    if recent_assignment == nil
      flash[:notice] = 'You have not requested for any input data for this problem.  Please download an input first.'
      redirect_to :action => 'list' and return
    end

    if recent_assignment.expired?
      flash[:notice] = 'The current input is expired.  Please download a new input data.'
      redirect_to :action => 'list' and return
    end

    if recent_assignment.submitted
      flash[:notice] = 'You have already submitted an incorrect solution for this input.  Please download a new input data.'
      redirect_to :action => 'list' and return
    end

    if params[:file] == nil
      flash[:notice] = 'You have not submitted any output.'
      redirect_to :action => 'list' and return
    end

    submitted_solution = params[:file].read
    test_pair = recent_assignment.test_pair
    passed = test_pair.grade(submitted_solution)
    points = passed ? 100 : 0
    submission = Submission.new(:user => user,
                                :problem => problem,
                                :source => submitted_solution,
                                :source_filename => params['file'].original_filename,
                                :language_id => 0,
                                :submitted_at => Time.new.gmtime,
                                :graded_at => Time.new.gmtime,
                                :points => points)
    submission.save
    recent_assignment.submitted = true
    recent_assignment.save

    status = user.get_submission_status_for(problem)
    if status == nil
      status = SubmissionStatus.new :user => user, :problem => problem, :submission_count => 0
    end

    status.submission_count += 1
    status.passed = passed
    status.save
    
    if passed
      flash[:notice] = 'Correct solution.'
      user.update_codejom_status
    else
      flash[:notice] = 'Incorrect solution.'
    end
    redirect_to :action => 'list'
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

    all_problems = Problem.find_available_problems

    passed = {}
    sub_count = {}
    @user.submission_statuses.each do |status|
      if status.passed
        passed[status.problem_id] = true
      end
      sub_count[status.problem_id] = status.submission_count
    end

    @problems = all_problems.reject { |problem| passed.has_key? problem.id }

    @prob_submissions = Array.new
    @problems.each do |p|
      if sub_count.has_key? p.id
        @prob_submissions << { :count => sub_count[p.id] }
      else
        @prob_submissions << { :count => 0 }
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

end

