class TestPairAssignment < ActiveRecord::Base

  belongs_to :user
  belongs_to :test_pair
  belongs_to :problem

  def expired?
    return created_at + TEST_ASSIGNMENT_EXPIRATION_DURATION < Time.new.gmtime 
  end

end
