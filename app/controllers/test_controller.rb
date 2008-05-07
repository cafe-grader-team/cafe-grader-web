class TestController < ApplicationController

  SYSTEM_MODE_CONF_KEY = 'system.mode'

  before_filter :authenticate, :check_viewability

#
#  COMMENT OUT: filter in each action instead
#
#  before_filter :verify_time_limit, :only => [:submit]

  verify :method => :post, :only => [:submit],
         :redirect_to => { :action => :index }

  def index
    prepare_index_information
  end

  def submit
    @user = User.find(session[:user_id])

    @submitted_test_request = TestRequest.new_from_form_params(@user,params[:test_request])

    if @submitted_test_request.errors.length != 0
      prepare_index_information
      render :action => 'index' and return
    end

    if Configuration[SYSTEM_MODE_CONF_KEY]=='contest' and
        @user.site!=nil and @user.site.finished?
      @submitted_test_request.errors.add_to_base('Contest is over.')
      prepare_index_information
      render :action => 'index' and return
    end

    if @submitted_test_request.save
      redirect_to :action => 'index'
    else
      prepare_index_information
      render :action => 'index'
    end
  end
  
  def read
    user = User.find(session[:user_id])
    begin
      test_request = TestRequest.find(params[:id])
    rescue
      test_request = nil
    end
    if test_request==nil or test_request.user_id != user.id
      flash[:notice] = 'Invalid output'
      redirect_to :action => 'index'
      return
    end
    if test_request.output_file_name!=nil
      data = File.open(test_request.output_file_name).read(2048)
      if data==nil
        data=""
      end
      send_data(data,
                {:filename => 'output.txt',
                  :type => 'text/plain'})
      return
    end
    redirect_to :action => 'index'
  end

  def result
    @user = User.find(session[:user_id])
    begin
      @test_request = TestRequest.find(params[:id])
    rescue
      @test_request = nil
    end
    if @test_request==nil or @test_request.user_id != @user.id
      flash[:notice] = 'Invalid request'
      redirect_to :action => 'index'
      return
    end
  end
    
  protected
  
  def prepare_index_information
    @user = User.find(session[:user_id])
    @submissions = Submission.find_last_for_all_available_problems(@user.id)
    all_problems = @submissions.collect { |submission| submission.problem }
    @problems = []
    all_problems.each do |problem|
      if problem.test_allowed
        @problems << problem
      end
    end
    @test_requests = @user.test_requests
  end

  def check_viewability
    user = User.find(session[:user_id])
    if !Configuration.show_tasks_to?(user)
      redirect_to :controller => 'main', :action => 'list'
    end
    if (!Configuration.show_submitbox_to?(user)) and (action_name=='submit')
      redirect_to :controller => 'test', :action => 'index'
    end
  end

end
