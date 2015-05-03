class Login < ActiveRecord::Base
  belongs_to :user

  attr_accessible :ip_address, :logged_in_at, :user_id
end
