class MessagesController < ApplicationController

  before_filter :authenticate

  verify :method => :post, :only => ['create'],
         :redirect_to => { :action => 'list' }

  before_filter :admin_authorization, :only => ['console','show',
                                                'reply','hide','list_all']

  def list
    @user = User.find(session[:user_id])
    @messages = Message.find_all_sent_by_user(@user)
  end

  def console
    @user = User.find(session[:user_id])
    @messages = Message.find_all_system_unreplied_messages
  end

  def show
    @message = Message.find(params[:id])
  end

  def list_all
    @user = User.find(session[:user_id])
    @messages = Message.where(receiver_id: nil).order(:created_at)
  end

  def create
    user = User.find(session[:user_id])
    @message = Message.new(params[:message])
    @message.sender = user
    if !@message.save
      render :action => 'list' and return
    else
      flash[:notice] = 'New message posted'
      redirect_to :action => 'list'
    end
  end

  def reply
    user = User.find(session[:user_id])
    @message = Message.new(params[:r_message])
    @message.sender = user
    if !@message.save
      render :action => 'show' and return
    else
      flash[:notice] = 'Message replied'
      rep_msg = @message.replying_message
      rep_msg.replied = true
      rep_msg.save
      redirect_to :action => 'console'
    end
  end

  def hide
    message = Message.find(params[:id])
    message.replied = true
    message.save
    flash[:notice] = 'Message hided (just marked replied)'
    redirect_to :action => 'console'
  end

  protected
  def build_replying_message_hierarchy(user)
    @all_messages = {}


    # manually build replies hierarchy (to improve efficiency)
    [@messages, @replied_messages].each do |collection|
      collection.each do |m| 
        @all_messages[m.id] = {:msg => m, :replies => []}
      end
    end

    @all_messages.each do |m|
      rep_id = m.replying_message_id
      if @all_messages[rep_id]!=nil
        @all_messages[rep_id][:replies] << m
      end
    end
  end

end
