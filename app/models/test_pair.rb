# TestPair stores an input-solution pair for a problem.  This is used
# in a certain "test-pair"-type problem for the CodeJom competition
# which follows the Google Code Jam format, i.e., a participant only
# submits a solution to a single random input that the participant
# requested.  This input-solution pair is a TestPair.

class TestPair < ActiveRecord::Base
  belongs_to :problem    

  def grade(submitted_solution)
    sols = solution.split
    subs = submitted_solution.split
    if sols.length == subs.length
      subs.length.times do |i| 
        return false if subs[i]!=sols[i]
      end
      return true
    else
      return false
    end
  end
end
