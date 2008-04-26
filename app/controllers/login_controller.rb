class LoginController < ApplicationController

  def index
    # show login screen
    reset_session
    redirect_to :controller => 'main', :action => 'login'
  end

  def login
    if user = User.authenticate(params[:login], params[:password])
      session[:user_id] = user.id
      redirect_to :controller => 'main', :action => 'list'
      if user.admin?
        session[:admin] = true
      else
        session[:admin] = false
      end
    else
      flash[:notice] = 'Wrong password'
      redirect_to :controller => 'main', :action => 'login'
    end
  end

end
