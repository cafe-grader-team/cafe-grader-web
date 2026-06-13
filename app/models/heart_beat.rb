class HeartBeat < ApplicationRecord
  # attr_accessible :title, :body
  belongs_to :user

  #attr_accessible :ip_address
end
