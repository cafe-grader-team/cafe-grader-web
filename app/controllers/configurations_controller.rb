class ConfigurationsController < ApplicationController

  before_filter :authenticate
  before_filter { |controller| controller.authorization_by_roles(['admin'])}

  in_place_edit_for :grader_configuration, :key
  in_place_edit_for :grader_configuration, :type
  in_place_edit_for :grader_configuration, :value

  def index
    @configurations = GraderConfiguration.find(:all,
                                         :order => '`key`')
  end

  def reload
    GraderConfiguration.reload
    redirect_to :action => 'index'
  end

end
