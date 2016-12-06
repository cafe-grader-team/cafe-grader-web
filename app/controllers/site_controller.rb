class SiteController < ApplicationController

  before_filter :site_admin_authorization, :except => 'login'

  def login
    # Site administrator login
    @countries = Country.includes(:sites).all
    @country_select = @countries.collect { |c| [c.name, c.id] }
    
    @country_select_with_all = [['Any',0]]
    @countries.each do |country|
      @country_select_with_all << [country.name, country.id]
    end
    
    @site_select = []
    @countries.each do |country|
      country.sites.each do |site|
        @site_select << ["#{site.name}, #{country.name}", site.id]
      end
    end
    
    @default_site = Site.first if !GraderConfiguration['contest.multisites']
    
    render :action => 'login', :layout => 'empty'
  end

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
      redirect_to :controller => 'site', :action => 'login' and return
    end
    begin
      @site = Site.find(session[:site_id], :include => :country)
    rescue ActiveRecord::RecordNotFound
      @site = nil
    end
    if @site==nil
      redirect_to :controller => 'site', :action => 'login' and return
    end
  end

  private
    def site_params
      params.require(:site).permit()
    end

end
