# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  # Pick a unique cookie name to distinguish our session data from others'
  session :session_key => '_grader_session_id'

  protected
  def authenticate
    unless session[:user_id]
      redirect_to :controller => 'main', :action => 'login'
      return false
    end

    # check if run in single user mode
    if defined?(SINGLE_USER_MODE) and (SINGLE_USER_MODE)
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

end

