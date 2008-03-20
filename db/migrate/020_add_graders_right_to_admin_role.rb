class AddGradersRightToAdminRole < ActiveRecord::Migration
  def self.up
    admin_role = Role.find_by_name('admin')

    graders_right = Right.create(:name => 'graders_admin',
                                 :controller => 'graders',
                                 :action => 'all')
    
    admin_role.rights << graders_right;
    admin_role.save
  end

  def self.down
    graders_right = Right.find_by_name('graders_admin')
    graders_right.destroy
  end
end
