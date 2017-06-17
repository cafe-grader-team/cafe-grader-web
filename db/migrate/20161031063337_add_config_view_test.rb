class AddConfigViewTest < ActiveRecord::Migration
  def up
    GraderConfiguration.create key: 'right.view_testcase', value_type: 'boolean', value:'true', description:'When true, any user can view/download test data'
    #uglily and dirtily and shamelessly check other config and inifialize
    GraderConfiguration.where(key: 'right.user_hall_of_fame').first_or_create(value_type: 'boolean', value: 'false',
                                                                              description: 'If true, any user can access hall of fame page.')
    GraderConfiguration.where(key: 'right.multiple_ip_login').first_or_create(value_type: 'boolean', value: 'false',
                                                                              description: 'When change from true to false, a user can login from the first IP they logged into afterward.')
    GraderConfiguration.where(key: 'right.user_view_submission').first_or_create(value_type: 'boolean', value: 'false',
                                                                                 description: 'If true, any user can view submissions of every one.')
  end

  def down
    GraderConfiguration.where(key: 'right.view_testcase').destroy_all;
  end
end
