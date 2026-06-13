class VivaTurn < ApplicationRecord
  enum :role, {system: 0, assistant: 1, student: 2}
  enum :status, {ok: 0, processing: 1, error: 2}

  belongs_to :submission

  validates :content, presence: true, if: -> { student? || (assistant? && ok?) }
  validates :sequence, presence: true, uniqueness: {scope: :submission_id}

  # How long a :processing turn is allowed to sit before fail_stale!
  # treats it as a stuck job. Generous enough to outlast slow LLM
  # calls plus retry backoff; short enough that a user who refreshes
  # eventually sees a real error and a retry button.
  STALE_AFTER = 10.minutes

  scope :ordered, -> { order(:sequence) }
  scope :assistant_turns, -> { where(role: :assistant) }

  # "Stuck" = a viva turn currently blocking a student on an ACTIVE
  # (status :submitted) interview. Covers two cases:
  #   1. :error — LLM call already failed and someone needs to Retry.
  #   2. :processing for longer than STALE_AFTER — sweeper hasn't
  #      promoted it to :error yet, but the user is already blocked.
  # Used by GradersController#index to surface count + the
  # stuck_viva_turns list page.
  scope :stuck, -> {
    joins(:submission)
      .assistant_turns
      .where(submissions: {status: Submission.statuses[:submitted]})
      .where(
        "(viva_turns.status = ? AND viva_turns.updated_at < ?) OR viva_turns.status = ?",
        statuses[:processing], STALE_AFTER.ago,
        statuses[:error]
      )
  }

  before_validation :assign_sequence_if_blank, on: :create

  def self.cost_summary_for(submissions)
    where(submission_id: submissions).assistant_turns.sum(:cost) || 0.0
  end

  # Marks any :processing assistant turn that has been quiet for longer
  # than STALE_AFTER as :error so the user is unblocked. Runs from
  # a Solid Queue recurring task (see config/recurring.yml). Without
  # this, a job that crashes the worker process — or any failure path
  # we forgot to wrap — leaves the turn stuck in :processing and the
  # student sees "Interviewer is thinking..." forever.
  def self.fail_stale!(threshold: STALE_AFTER, now: Time.zone.now)
    stale = where(role: :assistant, status: :processing)
              .where("updated_at < ?", now - threshold)
    count = 0
    stale.find_each do |turn|
      turn.update(
        status:  :error,
        content: "Interviewer timed out (no response after #{threshold.inspect}). " \
                 "Use the Retry button to try again."
      )
      count += 1
    end
    Rails.logger.info "VivaTurn.fail_stale!: marked #{count} stuck turn(s) as :error" if count.positive?
    count
  end

  private

  def assign_sequence_if_blank
    return if sequence.present?
    return unless submission

    submission.with_lock do
      self.sequence = (submission.viva_turns.maximum(:sequence) || -1) + 1
    end
  end
end
