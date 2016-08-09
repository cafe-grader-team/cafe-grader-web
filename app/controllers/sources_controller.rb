class SourcesController < ApplicationController
  before_filter :authenticate

  def direct_edit
    @problem = Problem.find(params[:pid])
    @source = ''
  end

  def direct_edit_submission
    @submission = Submission.find(params[:sid])
    @source = @submission.source.to_s
    @problem = @submission.problem
    @lang_id = @submission.language.id
    render 'direct_edit'
  end

  def get_latest_submission_status
    @problem = Problem.find(params[:pid])
    @submission = Submission.find_last_by_user_and_problem(params[:uid],params[:pid])
    puts User.find(params[:uid]).login
    puts Problem.find(params[:pid]).name
    puts 'nil' unless @submission
    respond_to do |format|
      format.js
    end
  end
end
