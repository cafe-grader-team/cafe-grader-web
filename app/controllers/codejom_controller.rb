class CodejomController < ApplicationController

  before_filter :admin_authorization
  before_filter :authenticate

  def index
    @user = User.find(session[:user_id])
    @problems = Problem.find(:all)
    @available_problems = @problems.find_all {|p| not p.available }
    @activated_problems = @problems.find_all {|p| p.available }
  end

end
