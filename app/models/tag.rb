class Tag < ApplicationRecord
  validates :name, presence: true

  # llm_prompt = AI-helper (Llm::CommentAssist) system prompt.
  # viva_conduct = shared examiner persona for viva problems.
  # Both are staff-only: they carry prompt/rubric-adjacent text that must
  # never be student-visible, so `public` is coerced off below.
  enum :kind, {normal: 0, topic: 1, llm_prompt: 2, viva_conduct: 3}
  has_many :problems_tags, class_name: 'ProblemTag'
  has_many :problems, through: :problems_tags

  has_many_attached :files

  before_validation :force_private_for_llm_kinds

  def llm_kind?
    llm_prompt? || viva_conduct?
  end

  private

  def force_private_for_llm_kinds
    self.public = false if llm_kind?
  end
end
