class AddAdminAndRoles < ActiveRecord::Migration
  def self.up
    root = User.new(:login => 'root',
		    :full_name => 'Administrator',
		    :alias => 'root')
    root.password = 'ioionrails';
    root.encrypt_new_password

    role = Role.create(:name => 'admin')
    root.roles << role;
    root.save

    user_admin_right = Right.create(:name => 'user_admin',
				    :controller => 'user_admin',
				    :action => 'all')
    problem_admin_right = Right.create(:name=> 'problem_admin',
				       :controller => 'problems',
				       :action => 'all')

    role.rights << user_admin_right;
    role.rights << problem_admin_right;
    role.save
  end

  def self.down
    admin_role = Role.find_by_name('admin')
    admin_role.destroy unless admin_role==nil

    admin_right = Right.find_by_name('user_admin')
    admin_right.destroy unless admin_right==nil

    admin_right = Right.find_by_name('problem_admin')
    admin_right.destroy unless admin_right==nil

    root = User.find_by_login('root')
    root.destroy unless root==nil
  end
end
