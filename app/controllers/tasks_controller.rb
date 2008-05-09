class TasksController < ApplicationController

  before_filter :authenticate, :check_viewability

  def index
    redirect_to :action => 'list'
  end

  def list
    @problems = Problem.find_available_problems
    @user = User.find(session[:user_id])
  end

  def view
    file_name = "#{RAILS_ROOT}/data/tasks/#{params[:file]}"
    if !FileTest.exists?(file_name)
      redirect_to :action => 'index' and return
    end
    # ask Apache to send the file
    response.headers['X-Sendfile'] = file_name
    render :nothing => true
  end

  protected

  def check_viewability
    user = User.find(session[:user_id])
    if user==nil or !Configuration.show_tasks_to?(user)
      redirect_to :controller => 'main', :action => 'list'
      return false
    end
  end

end
