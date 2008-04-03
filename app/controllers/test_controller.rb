class TestController < ApplicationController

  before_filter :authenticate

  verify :method => :post, :only => [:submit],
         :redirect_to => { :action => :index }

  def index
    @user = User.find(session[:user_id])
    prepare_index_information
    @test_requests = @user.test_requests
  end

  def submit
    @user = User.find(session[:user_id])
    test_request = TestRequest.new_from_form_params(@user,params[:test_request])
    if test_request.save
      redirect_to :action => 'index'
    else
      flash[:notice] = 'Error saving your test submission'
      redirect_to :action => 'index'
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
    @submissions = Submission.find_last_for_all_available_problems(@user.id)
    @problems = @submissions.collect { |submission| submission.problem }
  end

end
