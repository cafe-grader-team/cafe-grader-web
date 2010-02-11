class StatusesController < ApplicationController

  def index
    if not SHOW_CONTEST_STATUS
      render :status => 403 and return
    end

    problem_count = Problem.available_problem_count

    @dead_users = []
    @level_users = {}
    @levels = (0..CODEJOM_MAX_ALIVE_LEVEL)
    @levels.each { |l| @level_users[l] = [] }
    User.find(:all).find_all{|user| not user.admin? }.each do |user|
      user.update_codejom_status
      user.codejom_status(true)  # reload

      if not user.codejom_status.alive
        @dead_users << user
      else
        @level_users[user.codejom_level] << user
      end
    end

    respond_to do |format|
      format.html 
      format.xml do 
        render :template => 'statuses/index.xml.erb'
      end
    end
  end

end
