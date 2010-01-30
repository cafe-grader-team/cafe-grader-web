class ContestsController < ApplicationController

  before_filter :admin_authorization

  def index
  end

  def user_stat
    if not Configuration.indv_contest_mode?
      redirect_to :action => 'index' and return
    end

    @users = User.find(:all)
    @start_times = {}
    UserContestStat.find(:all).each do |stat|
      @start_times[stat.user_id] = stat.started_at
    end
  end

  def clear_stat
    user = User.find(params[:id])
    if user.contest_stat!=nil
      user.contest_stat.destroy
    end
    redirect_to :action => 'user_stat'
  end

  def clear_all_stat
    if not Configuration.indv_contest_mode?
      redirect_to :action => 'index' and return
    end

    UserContestStat.delete_all()
    flash[:notice] = 'All start time statistic cleared.'
    redirect_to :action => 'index'
  end

end
