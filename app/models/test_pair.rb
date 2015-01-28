class TestPair < ActiveRecord::Base
  belongs_to :problem

  def self.get_for(problem, is_private)
    return TestPair.where(:problem_id => problem.id,
                          :is_private => is_private).first
  end
end
