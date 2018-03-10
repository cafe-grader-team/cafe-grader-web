class Tag < ActiveRecord::Base
  has_many :problems_tags, class_name: ProblemTag
  has_many :problems, through: :problems_tags
end
