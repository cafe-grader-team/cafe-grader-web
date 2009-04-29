class GraderMessage < ActiveRecord::Base

  belongs_to :taken_grader_process, :class_name => :grader_process

  GRADE_SUBMISSION = 1
  GRADE_TEST_REQUEST = 2
  STOP = 3

  RECIPIENT_ANY = -1

  def self.create_message(recipient, command, options=nil, target_id=nil)
    recipient_id = recipient
    if recipient == :any
      recipient_id = GraderMessage::RECIPIENT_ANY
    end
    
    GraderMessage.create(:grader_process_id => recipient_id,
                         :command => command,
                         :options => options,
                         :target_id => target_id,
                         :taken => false)
  end

  def self.create_grade_submission(mode,submission)
    GraderMessage.create_message(:any,
                                 GraderMessage::GRADE_SUBMISSION,
                                 mode,
                                 submission.id)
  end
  
  def self.create_grade_test_request(mode,test_request)
    GraderMessage.create_message(:any,
                                 GraderMessage::GRADE_TEST_REQUEST,
                                 mode,
                                 test_request.id)
  end
  
  def self.create_stop(grader_process_id)
    GraderMessage.create_message(grader_process_id,
                                 GraderMessage::STOP)
  end

  def self.get_message_for(recipient_id, accepting_commands=:all)
    command_conditions = 
      GraderMessage.build_command_conditions(accepting_commands)
    recp_conditions= "((`grader_process_id` = #{recipient_id.to_i})" +
      " OR (`grader_process_id` = #{GraderMessage::RECIPIENT_ANY}))"

    message = nil   # need this to bind message in do-block for transaction
    begin
      GraderMessage.transaction do
        message = GraderMessage.find(:first, 
                                     :order => "created_at", 
                                     :conditions => 
                                     "(`taken` = 0)" + 
                                     " AND (#{recp_conditions})" + 
                                     " AND (#{command_conditions})",
                                     :lock => true)
        if message!=nil
          message.taken = true
          message.taken_grader_process_id = recipient_id
          message.save!
        end
      end
      
    rescue
      message = nil

    end
    
    message
  end
  
  protected
  
  def self.build_command_conditions(accepting_commands)
    if accepting_commands==:all
      return '(1=1)'
    else
      conds = []
      accepting_commands.each do |command|
        conds << "(`command` = #{command.to_i})"
      end
      return "(" + conds.join(" OR ") + ")"
    end
  end
  
end
