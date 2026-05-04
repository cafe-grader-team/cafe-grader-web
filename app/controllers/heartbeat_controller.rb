class HeartbeatController < ApplicationController
  before_action :check_valid_login

  def edit
    res = GraderConfiguration['right.heartbeat_response']
    res.strip! if res
    full = GraderConfiguration['right.heartbeat_response_full']
    full.strip! if full

    if full && full != ''
      l = Login.where(ip_address: request.remote_ip).last
      @user = l&.user
      if @user&.solve_all_available_problems?
        render plain: (full || 'OK')
      else
        render plain: (res || 'OK')
      end
    else
      render plain: (GraderConfiguration['right.heartbeat_response'] || 'OK')
    end
  end
end
