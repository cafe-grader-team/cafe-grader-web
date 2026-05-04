class ConfigurationsController < ApplicationController
  before_action :admin_authorization
  before_action :set_config, only: [:update, :toggle, :edit]

  def index
    @configurations = GraderConfiguration.order(:key)

    # pick the first key of the group name
    first_key = GraderConfiguration.pluck("grader_configurations.key").map { |x| x[0...(x.index('.'))] }.uniq.sort
    pre_defined_group = %w[chula ui right system]
    missing_group_less_contest = first_key - pre_defined_group - ['contest']

    # default grouping
    @group = [ %w[chula ui], 'right', 'system']

    # add any missing group
    @group += missing_group_less_contest
  end

  def edit
  end

  def reload
    GraderConfiguration.read_config
    redirect_to action: 'index'
  end

  def clear_user_ip
    User.clear_last_login
    @toast = {title: 'User Device Lock', body: 'Device locks of all users are cleared. The users can now log in from a new device'}
    render 'turbo_toast'
  end

  def update
    respond_to do |format|
      if @config.update(configuration_params)
        format.json { head :ok }
        format.turbo_stream
      end
    end
  end

  def toggle
    if @config.value == "true"
      @config.update(value: "false")
    else
      @config.update(value: "true")
    end

    # hook
    if @config.key == GraderConfiguration::SINGLE_USER_KEY && @config.value == 'true'
      GraderConfiguration.update_min_last_login
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  def set_exam_right
    value = params[:value] || 'false'
    GraderConfiguration.set_exam_mode(value)
    redirect_to action: 'index'
  end

private
  def configuration_params
    params.require(:grader_configuration).permit(:key, :value_type, :value, :description)
  end

  def set_config
    @config = GraderConfiguration.find(params[:id])
  end
end
