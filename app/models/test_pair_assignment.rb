class TestPairAssignment < ActiveRecord::Base
  belongs_to :problem
  belongs_to :test_pair
  belongs_to :user

  def expired?
    return created_at + TEST_ASSIGNMENT_EXPIRATION_DURATION < Time.new.gmtime 
  end
end
