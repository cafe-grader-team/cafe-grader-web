class HeartbeatController < ApplicationController
  before_filter :admin_authorization, :only => ['index']

  def edit
    @user = User.find_by_login(params[:id])
    unless @user
      render text: "LOGIN_NOT_FOUND"
      return
    end

    #hb = HeartBeat.where(user_id: @user.id, ip_address: request.remote_ip).first
    #puts "status = #{params[:status]}"
    #if hb
    #  if params[:status]
    #    hb.status = params[:status]
    #    hb.save
    #  end
    #  hb.touch
    #else
    #  HeartBeat.creae(user_id: @user.id, ip_address: request.remote_ip)
    #end
    HeartBeat.create(user_id: @user.id, ip_address: request.remote_ip, status: params[:status])

    render text: (GraderConfiguration['right.heartbeat_response'] || 'OK')
  end

  def index
    @hb = HeartBeat.where("updated_at >= ?",Time.zone.now-2.hours).includes(:user).order(:user_id).all
    @num = HeartBeat.where("updated_at >= ?",Time.zone.now-5.minutes).count
  end
end
