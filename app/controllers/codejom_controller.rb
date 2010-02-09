class CodejomController < ApplicationController

  before_filter :admin_authorization

  def index
    @user = User.find(session[:user_id])
    @problems = Problem.find(:all)
    @levels = @problems.collect {|p| p.level}.uniq.sort
    @available_problems = {}
    @levels.each do |level|
      @available_problems[level] = []
    end
    @problems.find_all {|p| not p.available }.each do |problem|
      @available_problems[problem.level] << problem
    end
    @activated_problems = @problems.find_all {|p| p.available }
  end

  def random_problem
    level = params[:id].to_i

    problems = Problem.unavailable.level(level).all
    puts problems
    if problems.length!=0
      if problems.length != 1
        problem = problems[rand(problems.length)]
      else
        problem = problems[0]
      end
      problem.available = true
      problem.save
    end

    redirect_to :action => 'index'
  end

end
