class TestPairAssignment < ActiveRecord::Base
  belongs_to :user
  belongs_to :test_pair
  belongs_to :problem
end
