require 'pony'

class UsersController < ApplicationController

  before_filter :authenticate, :except => [:new, :register]

  verify :method => :post, :only => [:chg_passwd],
         :redirect_to => { :action => :index }

  in_place_edit_for :user, :alias_for_editing
  in_place_edit_for :user, :email_for_editing

  def index
    if !Configuration['system.user_setting_enabled']
      redirect_to :controller => 'main', :action => 'list'
    else
      @user = User.find(session[:user_id])
    end
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

  def new
    @user = User.new
    render :action => 'new', :layout => 'empty'
  end

  def register
    @user = User.new(params[:user])
    @user.password_confirmation = @user.password = User.random_password
    @user.activated = false
    if (@user.valid?) and (@user.save)
      send_confirmation_email(@user)
      render :action => 'new_splash', :layout => 'empty'
    else
      @user.errors.add_to_base("Email cannot be blank") if @user.email==''
      render :action => 'new', :layout => 'empty'
    end
  end

  protected

  def send_confirmation_email(user)
  end
  
end
