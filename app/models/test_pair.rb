# TestPair stores an input-solution pair for a problem.  This is used
# in a certain "test-pair"-type problem for the CodeJom competition
# which follows the Google Code Jam format, i.e., a participant only
# submits a solution to a single random input that the participant
# requested.  This input-solution pair is a TestPair.

class TestPair < ActiveRecord::Base
  belongs_to :problem    
end
