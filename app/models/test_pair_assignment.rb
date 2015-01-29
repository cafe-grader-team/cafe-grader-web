class TestPairAssignment < ActiveRecord::Base
  belongs_to :problem
  belongs_to :test_pair
  belongs_to :user

  def expired?
    return created_at + TEST_ASSIGNMENT_EXPIRATION_DURATION < Time.new.gmtime 
  end

  def self.create_for(user, problem, test_pair)
    assignment = TestPairAssignment.new
    assignment.user = user
    assignment.problem = problem
    assignment.test_pair = test_pair
    assignment.submitted = false
    assignment.save
    return assignment
  end
end
