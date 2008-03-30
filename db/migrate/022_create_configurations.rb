class CreateConfigurations < ActiveRecord::Migration
  def self.up
    create_table :configurations do |t|
      t.column :key, :string
      t.column :value_type, :string
      t.column :value, :string
      t.timestamps
    end

    Configuration.reset_column_information

    Configuration.create(:key => 'system.single_user_mode',
                         :value_type => 'boolean',
                         :value => 'false')

    Configuration.create(:key => 'ui.front.title',
                         :value_type => 'string',
                         :value => 'Grader')

    Configuration.create(:key => 'ui.front.welcome_message',
                         :value_type => 'string',
                         :value => 'Welcome!')

    Configuration.create(:key => 'ui.show_score',
                         :value_type => 'boolean',
                         :value => 'true')

    Configuration.create(:key => 'contest.time_limit',
                         :value_type => 'string',
                         :value => 'unlimited')

  end

  def self.down
    drop_table :configurations
  end
end
