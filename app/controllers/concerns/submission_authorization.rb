module SubmissionAuthorization
  extend ActiveSupport::Concern

  included do
    # these funcions requires
    #   @current_user
    #   @submission

    # This DOES NOT check whether the problem of the submission is availble
    # be sure to call can_view_problem first
    # requires @submission
    def can_view_submission
      return true if @current_user.can_view_submission?(@submission)
      unauthorized_redirect(msg: 'You are not authorized to view this submission')
    end
  end
end
