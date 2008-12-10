require 'tmail'
require 'net/smtp'

class UsersController < ApplicationController

  before_filter :authenticate, :except => [:new, :register, :confirm]

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
      if send_confirmation_email(@user)
        render :action => 'new_splash', :layout => 'empty'
      else
        render :action => 'email_error', :layout => 'empty'
      end
    else
      @user.errors.add_to_base("Email cannot be blank") if @user.email==''
      render :action => 'new', :layout => 'empty'
    end
  end

  def confirm
    login = params[:login]
    key = params[:activation]
    user = User.find_by_login(login)
    if (user) and (user.verify_activation_key(key))
      if user.valid?  # check uniquenss of email
        user.activated = true
        user.save
        @result = :successful
      else
        @result = :email_used
      end
    else
      @result = :failed
    end
    render :action => 'confirm', :layout => 'empty'
  end

  protected

  def send_confirmation_email(user)
    contest_name = Configuration['contest.name']
    activation_url = url_for(:action => 'confirm', 
                             :login => user.login, 
                             :activation => user.activation_key)
    home_url = url_for(:controller => 'main', :action => 'index')
    mail = TMail::Mail.new
    mail.to = user.email
    mail.from = Configuration['system.online_registration.from']
    mail.subject = "[#{contest_name}] Confirmation"
    mail.body = <<-EOF
Hello #{user.full_name},

You have registered for #{contest_name} (#{home_url}).  

Your login is: #{user.login}
Your password is: #{user.password}

Please follow the link:
#{activation_url}
to activate your user account.

If you did not register, please ignore this e-mail.

Thanks!
EOF

    smtp_server = Configuration['system.online_registration.smtp']

    begin
      Net::SMTP.start(smtp_server) do |smtp|
        smtp.send_message(mail.to_s, mail.from, mail.to)
      end
      result = true
    rescue
      result = false
    end

    return result
  end
  
end
