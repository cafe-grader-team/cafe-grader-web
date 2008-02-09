class MainController < ApplicationController

  before_filter :authenticate, :except => [:index, :login]

  layout 'application'

  verify :method => :post, :only => [:submit],
         :redirect_to => { :action => :index }


  def index
    redirect_to :action => 'login'
  end

  def login
    MainController.layout 'empty'
    reset_session
  end

  def list
    @problems = Problem.find_available_problems
    @prob_submissions = Array.new
    @user = User.find(session[:user_id])
    @problems.each do |p|
      c, sub = Submission.find_by_user_and_problem(@user.id,p.id)
      @prob_submissions << [c,sub]
    end
  end

  def submit
    submission = Submission.new(params[:submission])
    submission.user_id = session[:user_id]
    submission.language_id = 0
    source = params['file'].read
    if source.length > 100_000
      flash[:notice] = 'Error: file too long'
    elsif (lang = Submission.find_language_in_source(source))==nil
      flash[:notice] = 'Error: cannot determine language used'
    elsif ((submission.problem_id==-1) and 
	   !(problem=Submission.find_problem_in_source(source)))
      flash[:notice] = 'Error: cannot determine problem submitted'
    elsif ((submission.problem_id==-1) and
	   (problem.available == false))
      flash[:notice] = 'Error: problem is not available'
    else
      submission.problem_id = problem.id if submission.problem_id == -1
      submission.source = source
      submission.language_id = lang.id
      submission.submitted_at = Time.new
      if submission.save == false
	flash[:notice] = 'Error saving your submission'
      elsif Task.create(:submission_id => submission.id) == false
	flash[:notice] = 'Error adding your submission to task queue'
      end
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
end
