class Login < ActiveRecord::Base
  attr_accessible :ip_address, :logged_in_at, :user_id
end
