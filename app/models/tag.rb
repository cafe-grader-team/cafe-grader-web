class Tag < ApplicationRecord
  validates :name, presence: true

  enum :kind, {normal: 0, topic: 1, llm_prompt: 2, viva_grounding: 3}
  has_many :problems_tags, class_name: 'ProblemTag'
  has_many :problems, through: :problems_tags

  has_many_attached :files

  def grounding_payload
    return params.to_s unless files.attached?

    extracted = files.map { |f| f.metadata['extracted_text'].to_s }.reject(&:blank?)
    [params.to_s, *extracted].reject(&:blank?).join("\n\n")
  end
end
