class RenameConfigurationsToGraderConfigurations < ActiveRecord::Migration
  def change
    rename_table 'configurations', 'grader_configurations'
  end
end
