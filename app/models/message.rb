class Message < ActiveRecord::Base

  belongs_to :sender, :class_name => "User"
  belongs_to :receiver, :class_name => "User"

  belongs_to :replying_message, :class_name => "Message"

  # commented manually do it
  #
  #has_many :replied_messages, {
  #  :class_name => "Message", 
  #  :foreign_key => "replying_message_id"
  #}
  #

  attr_accessor :replied_messages

  def self.find_all_sent_by_user(user)
    messages = user.messages
    replied_messages = user.replied_messages
    Message.build_replying_message_hierarchy messages, replied_messages
    return messages
  end
  
  def self.find_all_system_unreplied_messages
    self.find(:all, 
              :conditions => 'ISNULL(receiver_id) ' + 
                             'AND (ISNULL(replied) OR replied=0)',
              :order => 'created_at')
  end

  def self.build_replying_message_hierarchy(*args)
    # manually build replies hierarchy (to improve efficiency)
    all_messages = {}

    args.each do |collection|
      collection.each do |m| 
        all_messages[m.id] = m
        m.replied_messages = []
      end
    end

    all_messages.each_value do |m|
      rep_id = m.replying_message_id
      if all_messages[rep_id]!=nil
        all_messages[rep_id].add_replied_message(m)
      end
    end
  end

  def add_replied_message(m)
    if @replied_messages==nil
      @replied_messages = [m]
    else
      @replied_messages << m
    end
    @replied_messages
  end

end
