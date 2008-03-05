class MainController < ApplicationController

  before_filter :authenticate, :except => [:index, :login]

  verify :method => :post, :only => [:submit],
         :redirect_to => { :action => :index }


  def index
    redirect_to :action => 'login'
  end

  def login
    reset_session
    render :action => 'login', :layout => 'empty'
  end

  def list
    prepare_list_information
  end

  def submit
    @submission = Submission.new(params[:submission])
    @submission.user_id = session[:user_id]
    @submission.language_id = 0
    @submission.source = params['file'].read if params['file']!=''
    @submission.submitted_at = Time.new
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

  def get_source
    submission = Submission.find(params[:id])
    if submission.user_id == session[:user_id]
      fname = submission.problem.name + '.' + submission.language.ext
      send_data(submission.source, 
		{:filename => fname, 
                  :type => 'text/plain'})
    else
      flash[:notice] = 'Error viewing source'
    end
  end

  def test
    @user = User.find(session[:user_id])
    @submissions = Submission.find_last_for_all_available_problems(@user.id)
    @problems = @submissions.collect { |submission| submission.problem }
  end

  def test_submit
    @user = User.find(session[:user_id])
    test_request = TestRequest.new_from_form_params(@user,params[:test_request])
    if test_request.save
      redirect_to :action => 'test'
    else
      flash[:notice] = 'Error saving your test submission'
      render :action => 'test'
    end
  end

  protected
  def prepare_list_information
    @problems = Problem.find_available_problems
    @prob_submissions = Array.new
    @user = User.find(session[:user_id])
    @problems.each do |p|
      sub = Submission.find_last_by_user_and_problem(@user.id,p.id)
      if sub!=nil
        @prob_submissions << { :count => sub.number, :submission => sub }
      else
        @prob_submissions << { :count => 0, :submission => nil }
      end
    end
  end

end

