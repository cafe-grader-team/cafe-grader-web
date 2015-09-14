class HeartBeat < ActiveRecord::Base
  # attr_accessible :title, :body
  belongs_to :user

  #attr_accessible :ip_address
end
