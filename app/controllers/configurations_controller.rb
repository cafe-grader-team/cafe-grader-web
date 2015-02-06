class ConfigurationsController < ApplicationController

  before_filter :authenticate
  before_filter { |controller| controller.authorization_by_roles(['admin'])}


  def index
    @configurations = GraderConfiguration.find(:all,
                                         :order => '`key`')
  end

  def reload
    GraderConfiguration.reload
    redirect_to :action => 'index'
  end

  def update
    @config = GraderConfiguration.find(params[:id])
    respond_to do |format|
      if @config.update_attributes(params[:grader_configuration])
        format.json { head :ok }
      else
        format.json { respond_with_bip(@config) }
      end
    end
  end

end
