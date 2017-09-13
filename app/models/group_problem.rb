class GroupProblem < ActiveRecord::Base
  self.table_name = 'groups_problems'
  
  belongs_to :problem
  belongs_to :group
  validates_uniqueness_of :problem_id, scope: :group_id, message: ->(object, data) { "'#{Problem.find(data[:value]).full_name}' is already in the group" }
end
