# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  # Pick a unique cookie name to distinguish our session data from others'
  session :session_key => '_grader_session_id'

  SINGLE_USER_MODE_CONF_KEY = 'system.single_user_mode'

  def admin_authorization
    return false unless authenticate
    user = User.find(session[:user_id], :include => ['roles'])
    redirect_to :controller => 'main', :action => 'login' unless user.admin?
  end

  def authorization_by_roles(allowed_roles)
    return false unless authenticate
    user = User.find(session[:user_id])
    unless user.roles.detect { |role| allowed_roles.member?(role.name) }
      flash[:notice] = 'You are not authorized to view the page you requested'
      redirect_to :controller => 'main', :action => 'login'
      return false
    end
  end

  protected

  def authenticate
    unless session[:user_id]
      redirect_to :controller => 'main', :action => 'login'
      return false
    end

    #Configuration.reload
    # check if run in single user mode
    if (Configuration[SINGLE_USER_MODE_CONF_KEY])
      user = User.find(session[:user_id])
      if user==nil or user.login != 'root'
        redirect_to :controller => 'main', :action => 'login'
        return false
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
    if user.site.finished?
      flash[:notice] = 'Error: the contest on your site is over.'
      redirect_to :back
      return false
    end
    return true
  end

end

