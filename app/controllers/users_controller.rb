require 'net/smtp'

class UsersController < ApplicationController

  include MailHelperMethods

  before_filter :authenticate, :except => [:new, 
                                           :register, 
                                           :confirm, 
                                           :forget,
                                           :retrieve_password]

  before_filter :verify_online_registration, :only => [:new,
                                                       :register,
                                                       :forget,
                                                       :retrieve_password]
  before_filter :authenticate, :profile_authorization, only: [:profile]

  before_filter :admin_authorization, only: [:stat, :toggle_activate, :toggle_enable]


  verify :method => :post, :only => [:chg_passwd],
         :redirect_to => { :action => :index }

  #in_place_edit_for :user, :alias_for_editing
  #in_place_edit_for :user, :email_for_editing

  def index
    if !GraderConfiguration['system.user_setting_enabled']
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
    if(params[:cancel])
      redirect_to :controller => 'main', :action => 'login'
      return
    end
    @user = User.new(user_params)
    @user.password_confirmation = @user.password = User.random_password
    @user.activated = false
    if (@user.valid?) and (@user.save)
      if send_confirmation_email(@user)
        render :action => 'new_splash', :layout => 'empty'
      else
        @admin_email = GraderConfiguration['system.admin_email']
        render :action => 'email_error', :layout => 'empty'
      end
    else
      @user.errors.add(:base,"Email cannot be blank") if @user.email==''
      render :action => 'new', :layout => 'empty'
    end
  end

  def confirm
    login = params[:login]
    key = params[:activation]
    @user = User.find_by_login(login)
    if (@user) and (@user.verify_activation_key(key))
      if @user.valid?  # check uniquenss of email
        @user.activated = true
        @user.save
        @result = :successful
      else
        @result = :email_used
      end
    else
      @result = :failed
    end
    render :action => 'confirm', :layout => 'empty'
  end

  def forget
    render :action => 'forget', :layout => 'empty'
  end

  def retrieve_password
    email = params[:email]
    user = User.find_by_email(email)
    if user
      last_updated_time = user.updated_at || user.created_at || (Time.now.gmtime - 1.hour)
      if last_updated_time > Time.now.gmtime - 5.minutes
        flash[:notice] = 'The account has recently created or new password has recently been requested.  Please wait for 5 minutes'
      else
        user.password = user.password_confirmation = User.random_password
        user.save
        send_new_password_email(user)
        flash[:notice] = 'New password has been mailed to you.'
      end
    else
      flash[:notice] = I18n.t 'registration.password_retrieval.no_email'
    end
    redirect_to :action => 'forget'
  end

  def stat
    @user = User.find(params[:id])
    @submission = Submission.joins(:problem).where(user_id: params[:id])
    @submission = @submission.where('problems.available = true') unless current_user.admin?

    range = 120
    @histogram = { data: Array.new(range,0), summary: {} }
    @summary = {count: 0, solve: 0, attempt: 0}
    problem = Hash.new(0)

    @submission.find_each do |sub|
      #histogram
      d = (DateTime.now.in_time_zone - sub.submitted_at) / 24 / 60 / 60
      @histogram[:data][d.to_i] += 1 if d < range

      @summary[:count] += 1
      next unless sub.problem
      problem[sub.problem] = [problem[sub.problem], ( (sub.try(:points) || 0) >= sub.problem.full_score) ? 1 : 0].max
    end

    @histogram[:summary][:max] = [@histogram[:data].max,1].max
    @summary[:attempt] = problem.count
    problem.each_value { |v| @summary[:solve] += 1 if v == 1 }
  end

  def toggle_activate
    @user = User.find(params[:id])
    @user.update_attributes( activated:  !@user.activated? )
    respond_to do |format|
      format.js { render partial: 'toggle_button',
                  locals: {button_id: "#toggle_activate_user_#{@user.id}",button_on: @user.activated? } }
    end
  end

  def toggle_enable
    @user = User.find(params[:id])
    @user.update_attributes( enabled:  !@user.enabled? )
    respond_to do |format|
      format.js { render partial: 'toggle_button',
                  locals: {button_id: "#toggle_enable_user_#{@user.id}",button_on: @user.enabled? } }
    end
  end

  protected

  def verify_online_registration
    if !GraderConfiguration['system.online_registration']
      redirect_to :controller => 'main', :action => 'login'
    end
  end

  def send_confirmation_email(user)
    contest_name = GraderConfiguration['contest.name']
    activation_url = url_for(:action => 'confirm', 
                             :login => user.login, 
                             :activation => user.activation_key)
    home_url = url_for(:controller => 'main', :action => 'index')
    mail_subject = "[#{contest_name}] Confirmation"
    mail_body = t('registration.email_body', {
                    :full_name => user.full_name,
                    :contest_name => contest_name,
                    :login => user.login,
                    :password => user.password,
                    :activation_url => activation_url,
                    :admin_email => GraderConfiguration['system.admin_email']
                  })

    logger.info mail_body

    send_mail(user.email, mail_subject, mail_body)
  end
  
  def send_new_password_email(user)
    contest_name = GraderConfiguration['contest.name']
    mail_subject = "[#{contest_name}] Password recovery"
    mail_body = t('registration.password_retrieval.email_body', {
                    :full_name => user.full_name,
                    :contest_name => contest_name,
                    :login => user.login,
                    :password => user.password,
                    :admin_email => GraderConfiguration['system.admin_email']
                  })

    logger.info mail_body

    send_mail(user.email, mail_subject, mail_body)
  end

  # allow viewing of regular user profile only when options allow so
  # only admins can view admins profile
  def profile_authorization
    #if view admins' profile, allow only admin
    return false unless(params[:id])
    user = User.find(params[:id])
    return false unless user
    return admin_authorization if user.admin?
    return true if GraderConfiguration["right.user_view_submission"]

    #finally, we allow only admin
    admin_authorization
  end

  private
    def user_params
      params.require(:user).permit(:login, :full_name, :email)
    end

end
