class StatusesController < ApplicationController

  def index
    problem_count = Problem.available_problem_count

    @dead_users = []
    @level_users = {}
    @levels = (0..CODEJOM_MAX_ALIVE_LEVEL)
    @levels.each { |l| @level_users[l] = [] }
    User.find(:all).each do |user|
      if user.codejom_status==nil
        user.update_codejom_status
        user.codejom_status(true)  # reload
      end

      if not user.codejom_status.alive
        @dead_users << user
      else
        @level_users[user.codejom_level] << user
      end
    end
  end

end
