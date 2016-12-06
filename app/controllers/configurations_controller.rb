class ConfigurationsController < ApplicationController

  before_filter :authenticate
  before_filter { |controller| controller.authorization_by_roles(['admin'])}


  def index
    @configurations = GraderConfiguration.order(:key)
    @group = GraderConfiguration.pluck("grader_configurations.key").map{ |x| x[0...(x.index('.'))] }.uniq.sort
  end

  def reload
    GraderConfiguration.reload
    redirect_to :action => 'index'
  end

  def update
    @config = GraderConfiguration.find(params[:id])
    User.clear_last_login if @config.key == GraderConfiguration::MULTIPLE_IP_LOGIN_KEY and @config.value == 'true' and params[:grader_configuration][:value] == 'false'
    respond_to do |format|
      if @config.update_attributes(configuration_params)
        format.json { head :ok }
      else
        format.json { respond_with_bip(@config) }
      end
    end
  end

private
  def configuration_params
    params.require(:grader_configuration).permit(:key,:value_type,:value,:description)
  end

end
