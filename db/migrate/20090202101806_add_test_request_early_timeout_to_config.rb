class AddTestRequestEarlyTimeoutToConfig < ActiveRecord::Migration
  def self.up
    # If Configuration['contest.test_request.early_timeout'] is true
    #   the user will not be able to use test request at 30 minutes
    #   before the contest ends.

    Configuration.create(:key => 'contest.test_request.early_timeout',
                         :value_type => 'boolean',
                         :value => 'false')
  end

  def self.down
    Configuration.find_by_key('contest.test_request.early_timeout').destroy
  end
end
