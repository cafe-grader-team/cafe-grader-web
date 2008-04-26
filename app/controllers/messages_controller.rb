class MessagesController < ApplicationController

  before_filter :authenticate

  verify :method => :post, :only => ['create'],
         :redirect_to => { :action => 'list' }

  before_filter :only => ['console','show'] do |controller| 
    controller.authorization_by_roles(['admin'])
  end

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
