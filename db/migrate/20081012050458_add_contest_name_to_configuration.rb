class AddContestNameToConfiguration < ActiveRecord::Migration
  def self.up
    # Configuration['contest.name']:
    #   it will be shown on the user header bar

    Configuration.create(:key => 'contest.name',
                         :value_type => 'string',
                         :value => 'Grader')
  end

  def self.down
    Configuration.find_by_key('contest.name').destroy
  end
end
