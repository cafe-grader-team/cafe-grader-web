class AddAdminEmailToConfig < ActiveRecord::Migration
  def self.up
    Configuration.create(:key => 'system.admin_email',
                         :value_type => 'string',
                         :value => 'admin@admin.email')
  end

  def self.down
    Configuration.find_by_key('system.admin_email').destroy
  end
end
