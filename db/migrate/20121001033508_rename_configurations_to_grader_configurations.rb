class RenameConfigurationsToGraderConfigurations < ActiveRecord::Migration[4.2]
  def change
    rename_table 'configurations', 'grader_configurations'
  end
end
