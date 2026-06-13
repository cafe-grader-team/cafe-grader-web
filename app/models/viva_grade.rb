class VivaGrade < ApplicationRecord
  belongs_to :submission

  validates :submission_id, uniqueness: true

  def rubric_breakdown
    return {} if score_json.blank?
    JSON.parse(score_json)
  rescue JSON::ParserError
    {}
  end
end
