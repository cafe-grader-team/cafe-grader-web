class ProblemTag < ActiveRecord::Base
  self.table_name = 'problems_tags'

  belongs_to :problem
  belongs_to :tag

  validates_uniqueness_of :problem_id, scope: :tag_id, message: ->(object, data) { "'#{Problem.find(data[:value]).full_name}' is already has this tag" }
end
