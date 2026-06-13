class GraderError < RuntimeError
  attr_reader :end_job
  attr_reader :update_submission
  attr_reader :submission_id
  attr_reader :message_for_user

  def initialize(msg = "Generic grader error",
                 end_job: true,                   # should the job status become "error"
                 update_submission: true,         # do we update the status of the submission
                 submission_id: nil,              # which submission?
                 message_for_user: msg)           # with what message
    @end_job = end_job
    @update_submission = update_submission
    @message_for_user = message_for_user
    @submission_id = submission_id
    super(msg)
  end
end
