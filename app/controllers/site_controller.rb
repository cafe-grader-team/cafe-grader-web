class SiteController < ApplicationController

  before_filter :site_admin_authorization

  def index
    if @site.started
      render :action => 'started', :layout => 'empty'
    else
      render :action => 'prompt', :layout => 'empty'
    end
  end

  def start
    @site.started = true
    @site.start_time = Time.new.gmtime
    @site.save
    redirect_to :action => 'index'
  end

  def logout
    reset_session
    redirect_to :controller => 'main', :action => 'login'
  end

  protected
  def site_admin_authorization
    if session[:site_id]==nil
      redirect_to :controller => 'main', :action => 'login' and return
    end
    begin
      @site = Site.find(session[:site_id], :include => :country)
    rescue ActiveRecord::RecordNotFound
      @site = nil
    end
    if @site==nil
      redirect_to :controller => 'main', :action => 'login' and return
    end
  end

end
