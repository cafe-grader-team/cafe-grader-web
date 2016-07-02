class SourcesController < ApplicationController
  before_filter :authenticate, :except => [:index, :login]

  def direct_edit
    @problem = Problem.find_by_id(params[:pid])
  end
end
