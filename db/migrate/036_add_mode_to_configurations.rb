class AddModeToConfigurations < ActiveRecord::Migration
  def self.up

    # Configuration['system.mode']:
    #  * 'standard' mode
    #  * 'contest' mode (check site start time/stop time)
    #  * 'analysis' mode (show results, no new submissions)

    Configuration.create(:key => 'system.mode',
                         :value_type => 'string',
                         :value => 'standard')
  end

  def self.down
    Configuration.find_by_key('system.mode').destroy
  end
end
