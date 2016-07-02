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

end
