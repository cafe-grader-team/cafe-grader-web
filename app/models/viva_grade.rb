# One row per grader run of a viva session (design
# docs/superpowers/specs/2026-09-23-viva-grade-history-design.md). The row
# with superseded_at IS NULL is the submission's CURRENT grade — the run whose
# total_points is copied to submissions.points; at most one per submission.
# Every other row is history, labelled by superseded_reason:
#   replaced — a later run was adopted (superseded_by_id points at it)
#   lower    — the never-lower rule kept the older grade; this run never counted
#   error    — this run produced no grade (message in `error`)
#   reverted — displaced by Make current or viva:regrade_revert (superseded_by_id
#              points at the re-adopted run)
# A run is written non-current first and adopted by Submission#adopt_viva_grade!
# once it is a grade; superseded_reason stays nil for the moment in between.
# Nothing here is ever destroyed.
class VivaGrade < ApplicationRecord
  REASONS = %w[replaced lower error reverted].freeze

  belongs_to :submission
  belongs_to :superseded_by, class_name: 'VivaGrade', optional: true
  belongs_to :requested_by,  class_name: 'User',      optional: true

  scope :current, -> { where(superseded_at: nil) }
  scope :history, -> { where.not(superseded_at: nil) }

  # At most one current run per submission. MySQL cannot enforce "one NULL"
  # with an index, so the model does; callers change currency under the
  # submission's row lock (Submission#adopt_viva_grade!).
  validates :submission_id,
            uniqueness: {conditions: -> { where(superseded_at: nil) }, message: 'already has a current grade'},
            if: -> { superseded_at.nil? }
  validates :superseded_reason, inclusion: {in: REASONS}, allow_nil: true

  def current?     = superseded_at.nil?
  def valid_grade? = total_points.present?
  def failed?      = !valid_grade?

  def supersede!(reason:, by: nil, now: Time.zone.now)
    update!(superseded_at: now, superseded_reason: reason, superseded_by_id: by&.id)
  end

  # Records a run that produced no grade — the reply was not a grade after
  # the one re-ask (Llm::VivaGradeAssist#handle_error), or the job's retries
  # were exhausted on a transport error (Llm::VivaGradeAssistJob). `grade` is
  # the row handle_response may already have saved for this run; nil when the
  # failure came before any response. Never touches the submission: the
  # caller decides whether it has a valid grade to keep.
  def self.record_failure!(submission, error:, grade: nil, model: nil, requested_by_id: nil, batch_id: nil,
                           rubric_version: nil, now: Time.zone.now)
    message = error.to_s.truncate(2000)
    if grade&.persisted?
      # The stored value, not the in-memory one: a stale handle (e.g. a run
      # adopted and then displaced elsewhere) must never be made current here.
      grade.update!(superseded_at: grade.superseded_at_in_database || now, superseded_reason: 'error', error: message)
      grade
    else
      submission.viva_grades.create!(superseded_at: now, superseded_reason: 'error', error: message, graded_at: now,
                                     llm_model: model, requested_by_id: requested_by_id, batch_id: batch_id,
                                     rubric_version: rubric_version)
    end
  end

  def rubric_breakdown
    return {} if score_json.blank?
    JSON.parse(score_json)
  rescue JSON::ParserError
    {}
  end
end
