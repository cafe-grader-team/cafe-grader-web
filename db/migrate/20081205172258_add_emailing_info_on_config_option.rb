class AddEmailingInfoOnConfigOption < ActiveRecord::Migration
  def self.up
    # If Configuration['system.online_registration'] is true, the
    # system allows online registration, and will use these
    # information for sending confirmation emails.
    Configuration.create(:key => 'system.online_registration.smtp',
                         :value_type => 'string',
                         :value => 'smtp.somehost.com')
    Configuration.create(:key => 'system.online_registration.from',
                         :value_type => 'string',
                         :value => 'your.email@address')
  end

  def self.down
    Configuration.find_by_key("system.online_registration.smtp").destroy
    Configuration.find_by_key("system.online_registration.from").destroy
  end
end
