class MessagesController < ApplicationController

  before_action :check_valid_login

  before_action :set_message, only: ['show', 'reply']

  before_action :admin_authorization, :only => ['console','show',
                                                'reply','hide','list_all']

  def index
    @messages = Message.find_all_sent_by_user(@current_user)
  end

  def console
    @messages = Message.find_all_system_unreplied_messages
  end

  def show
  end

  def list_all
    @messages = Message.where(receiver_id: nil).order(:created_at)
  end

  def create
    @message = Message.new(message_params)
    @message.sender = @current_user
    if @message.body == '' or !@message.save
      flash[:notice] = 'An error occurred'
    else
      flash[:notice] = 'New message posted'
    end
    redirect_to action: 'index'
  end

  def reply
    @r_message = Message.new(message_params)
    @r_message.receiver = @message.sender
    @r_message.sender = @current_user
    if @message.body == '' or !@message.save
      flash[:notice] = 'An error occurred'
      redirect_to :action => 'show', :id => @message.replying_message_id
    else
      flash[:notice] = 'Message replied'
      @message.replied = true
      @message.replying_message = @r_message
      @message.save
      redirect_to :action => 'console'
    end
  end

  def hide
    message = Message.find(params[:id])
    message.replied = true
    message.save
    flash[:notice] = 'Message hidden (just marked replied)'
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

    def set_message
      @message = Message.find(params[:id])
    end

    def message_params
      params.require(:message).permit(:body)
    end

end
