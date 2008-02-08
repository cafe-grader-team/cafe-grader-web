class UsersController < ApplicationController

  before_filter :authenticate

  verify :method => :post, :only => [:chg_passwd],
         :redirect_to => { :action => :index }

  in_place_edit_for :user, :full_name
  in_place_edit_for :user, :alias_for_editing
  in_place_edit_for :user, :email_for_editing

  def index
    @user = User.find(session[:user_id])
  end

  def chg_passwd
    user = User.find(session[:user_id])
    user.password = params[:passwd]
    user.password_confirmation = params[:passwd_verify]
    if user.save
      flash[:notice] = 'password changed'
    else
      flash[:notice] = 'Error: password changing failed'
    end
    redirect_to :action => 'index'
  end

end
