class ApplicationController < ActionController::Base
  protect_from_forgery

  before_filter :current_user

  SINGLE_USER_MODE_CONF_KEY = 'system.single_user_mode'
  MULTIPLE_IP_LOGIN_CONF_KEY = 'right.multiple_ip_login'

  #report and redirect for unauthorized activities
  def unauthorized_redirect
    flash[:notice] = 'You are not authorized to view the page you requested'
    redirect_to :controller => 'main', :action => 'login'
  end

  # Returns the current logged-in user (if any).
  def current_user
    return nil unless session[:user_id]
    @current_user ||= User.find(session[:user_id])
  end

  def admin_authorization
    return false unless authenticate
    user = User.includes(:roles).find(session[:user_id])
    unless user.admin?
      unauthorized_redirect
      return false
    end
    return true
  end

  def authorization_by_roles(allowed_roles)
    return false unless authenticate
    user = User.find(session[:user_id])
    unless user.roles.detect { |role| allowed_roles.member?(role.name) }
      unauthorized_redirect
      return false
    end
  end

  def testcase_authorization
    #admin always has privileged
    if @current_user.admin?
      return true
    end

    unauthorized_redirect if GraderConfiguration["right.view_testcase"]
  end

  protected

  def authenticate
    unless session[:user_id]
      flash[:notice] = 'You need to login'
      if GraderConfiguration[SINGLE_USER_MODE_CONF_KEY]
        flash[:notice] = 'You need to login but you cannot log in at this time'
      end
      redirect_to :controller => 'main', :action => 'login'
      return false
    end

    # check if run in single user mode
    if GraderConfiguration[SINGLE_USER_MODE_CONF_KEY]
      user = User.find_by_id(session[:user_id])
      if user==nil or (not user.admin?)
        flash[:notice] = 'You cannot log in at this time'
        redirect_to :controller => 'main', :action => 'login'
        return false
      end
      unless user.enabled?
        flash[:notice] = 'Your account is disabled'
        redirect_to :controller => 'main', :action => 'login'
        return false
      end
      return true
    end

    if GraderConfiguration.multicontests? 
      user = User.find(session[:user_id])
      return true if user.admin?
      begin
        if user.contest_stat(true).forced_logout
          flash[:notice] = 'You have been automatically logged out.'
          redirect_to :controller => 'main', :action => 'index'
        end
      rescue
      end
    end
    return true
  end

  def authenticate_by_ip_address
    #this assume that we have already authenticate normally
    unless GraderConfiguration[MULTIPLE_IP_LOGIN_CONF_KEY]
      user = User.find(session[:user_id])
      if (not user.admin? and user.last_ip and user.last_ip != request.remote_ip)
        flash[:notice] = "You cannot use the system from #{request.remote_ip}. Your last ip is #{user.last_ip}"
        redirect_to :controller => 'main', :action => 'login'
        puts "CHEAT: user #{user.login} tried to login from '#{request.remote_ip}' while last ip is '#{user.last_ip}' at #{Time.zone.now}"
        return false
      end
      unless user.last_ip
        user.last_ip = request.remote_ip
        user.save
      end
    end
    return true
  end

  def authorization
    return false unless authenticate
    user = User.find(session[:user_id])
    unless user.roles.detect { |role|
	role.rights.detect{ |right|
	  right.controller == self.class.controller_name and
          (right.action == 'all' or right.action == action_name)
	}
      }
      flash[:notice] = 'You are not authorized to view the page you requested'
      #request.env['HTTP_REFERER'] ? (redirect_to :back) : (redirect_to :controller => 'login')
      redirect_to :controller => 'main', :action => 'login'
      return false
    end
  end

  def verify_time_limit
    return true if session[:user_id]==nil
    user = User.find(session[:user_id], :include => :site)
    return true if user==nil or user.site == nil
    if user.contest_finished?
      flash[:notice] = 'Error: the contest you are participating is over.'
      redirect_to :back
      return false
    end
    return true
  end

end
