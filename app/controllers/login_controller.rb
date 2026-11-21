class LoginController < ApplicationController
  include LoginThrottling

  @@authenticators = []

  def index
    # show login screen
    reset_session
    redirect_to controller: 'main', action: 'login'
  end

  def login
    if login_throttled?
      redirect_to login_main_path, alert: 'Too many failed login attempts. Please wait a few minutes and try again.'
      return
    end

    result = User.login_result(params[:login], params[:password])
    if result.refusal
      record_refused_login!
      redirect_to login_main_path, alert: User.outside_login_refused_message
      return
    end

    user = result.user || get_authenticated_user_via_authenticators(params[:login], params[:password])
    unless user
      record_login_failure!
      redirect_to login_main_path, alert: 'Wrong password'
      return
    end
    clear_login_failures!

    if (!GraderConfiguration['right.bypass_agreement']) && (!params[:accept_agree]) && !user.admin?
      redirect_to login_main_path, alert: 'You must accept the agreement before logging in'
      return
    end

    # The device lock (users.last_ip) is not touched here: check_valid_login
    # records the first browser seen after login and refuses every other one.

    # process logging in
    session[:user_id] = user.id
    session[:admin] = user.admin?
    session[:last_login] = Time.zone.now


    # save login information
    Login.create(user_id: user.id, ip_address: request.remote_ip, cookie: cookies.encrypted[:uuid])

    redirect_to controller: 'main', action: 'list'
  end

  def site_login
    begin
      site = Site.find(params[:login][:site_id])
    rescue ActiveRecord::RecordNotFound
      site = nil
    end
    if site==nil
      flash[:alert] = 'Wrong site'
      redirect_to controller: 'main', action: 'login'  and return
    end
    if (site.password) and (site.password == params[:login][:password])
      session[:site_id] = site.id
      redirect_to controller: 'site', action: 'index'
    else
      flash[:alert] = 'Wrong site password'
      redirect_to controller: 'site', action: 'login'
    end
  end

  def logout
    redirect_to root_path
  end

  def self.add_authenticator(authenticator)
    @@authenticators << authenticator
  end

  protected

  # Only reached when User.login_result found no user and no refusal.
  def get_authenticated_user_via_authenticators(login, password)
    user = nil
    @@authenticators.each do |authenticator|
      user ||= authenticator.authenticate(login, password)
    end
    user
  end
end
