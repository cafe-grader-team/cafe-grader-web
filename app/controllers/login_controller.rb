class LoginController < ApplicationController
  @@authenticators = []

  def index
    # show login screen
    reset_session
    redirect_to controller: 'main', action: 'login'
  end

  def login
    user = get_authenticated_user(params[:login], params[:password])
    unless user
      redirect_to login_main_path, alert: 'Wrong password'
      return
    end

    if (!GraderConfiguration['right.bypass_agreement']) && (!params[:accept_agree]) && !user.admin?
      redirect_to login_main_path, alert: 'You must accept the agreement before logging in'
      return
    end

    # store uuid when login
    if user.last_ip.nil?
      user.last_ip = cookies.encrypted[:uuid]
    else
      if user.last_ip != cookies.encrypted[:uuid]
        user.last_ip =cookies.encrypted[:uuid]
        # log different login
      end
    end

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

  def get_authenticated_user(login, password)
    if @@authenticators.empty?
      return User.authenticate(login, password)
    else
      user = User.authenticate(login, password)
      @@authenticators.each do |authenticator|
        if not user
          user = authenticator.authenticate(login, password)
        end
      end
      return user
    end
  end
end
