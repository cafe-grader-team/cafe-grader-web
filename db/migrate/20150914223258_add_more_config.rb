class AddMoreConfig < ActiveRecord::Migration
  def up
    GraderConfiguration.create key: 'right.bypass_agreement', value_type: 'boolean', value:'true', description:'When false, a check box to accept license agreement appear at login and the user must click accept'
  end

  def down
    
  end
end
