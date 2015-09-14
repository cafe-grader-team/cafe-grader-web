class HeartbeatController < ApplicationController
  def edit
    render layout: 'empty'
    @user = User.find_by_login(params[:id])
    return unless @user
    
    hb = HeartBeat.where(user_id: @user.id, ip_address: request.remote_ip).first
    if hb
      hb.touch
    else
      HeartBeat.create(user_id: @user.id, ip_address: request.remote_ip)
    end
  end
end
