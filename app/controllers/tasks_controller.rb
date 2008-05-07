class TasksController < ApplicationController

  before_filter :authenticate, :check_viewability

  def index
    redirect_to :action => 'list'
  end

  def list
    @problems = Problem.find_available_problems
    @user = User.find(session[:user_id])
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
