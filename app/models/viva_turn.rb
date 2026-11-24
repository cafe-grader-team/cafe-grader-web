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

  # A turn that was queued but never started running (llm_started_at nil) is
  # only stale after a longer grace — a queue backlog is not a stuck job, and
  # failing a still-queued turn showed the student a false "timed out" (the
  # 2026-09-09 exam queued turns up to ~7.7 min under one shared worker).
  # Note: Llm::VivaTurnAssist saves llm_started_at together with the reply, so
  # a turn still :processing always has it nil and, as of 4.7.3, every stuck
  # turn takes this 20-minute path; STALE_AFTER applies only if the start is
  # ever recorded when the call begins.
  QUEUE_STALE_AFTER = 20.minutes

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
        "(viva_turns.status = :processing AND ((viva_turns.llm_started_at IS NOT NULL AND viva_turns.llm_started_at < :run) OR (viva_turns.llm_started_at IS NULL AND viva_turns.updated_at < :queue))) OR viva_turns.status = :error",
        processing: statuses[:processing], error: statuses[:error],
        run: STALE_AFTER.ago, queue: QUEUE_STALE_AFTER.ago
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
  def self.fail_stale!(threshold: STALE_AFTER, queue_threshold: QUEUE_STALE_AFTER, now: Time.zone.now)
    stale = where(role: :assistant, status: :processing).where(
      "(llm_started_at IS NOT NULL AND llm_started_at < :run) OR (llm_started_at IS NULL AND updated_at < :queue)",
      run: now - threshold, queue: now - queue_threshold
    )
    count = 0
    stale.find_each do |turn|
      # name the wait that actually applied (it used to say 10 minutes for a
      # turn failed by the 20-minute queue rule)
      waited = turn.llm_started_at ? threshold : queue_threshold
      turn.update(
        status:  :error,
        content: "Interviewer timed out (no response after #{waited.inspect}). " \
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
