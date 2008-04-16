class TasksController < ApplicationController

  before_filter :authenticate


  def index
    redirect_to :action => 'list'
  end

  def list
    @problems = Problem.find_available_problems
    @user = User.find(session[:user_id])
  end

end
