class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  belongs_to :user

  enum :kind, {hint: 0, solution: 1, comment: 2, llm_assist: 3}
  enum :status, {ok: 0, processing: 1, error: 2} # used to indicate whether this comment is waiting to be updated (such as from AI API call)

  has_many :comment_reveals
  has_many :users_who_revealed, through: :comment_reveals, source: :user # More descriptive name

  # limit to only HINT
  HINT_KIND = self.kinds.select { |k| k[0...4] == 'hint' }

  scope :chargeable_for, ->(user, time_range = nil) {
    if time_range
      where(user: user, updated_at: time_range, kind: ['hint', 'llm_assist'])
    else
      where(user: user, kind: ['hint', 'llm_assist'])
    end
  }

  scope :hint_reveal_for_problems, ->(problems, time_range = nil) {
    if time_range
      Comment.joins(:comment_reveals)
        .where(commentable: problems, commentable_type: 'Problem')
        .where(comment_reveals: {created_at: time_range})
        .group('comment_reveals.user_id', :commentable_id)
    else
      Comment.joins(:comment_reveals)
        .where(commentable: problems, commentable_type: 'Problem')
        .group('comment_reveals.user_id', :commentable_id)
    end
  }

  # Hint reveals for `problems` by members of `contest`, each counted only
  # when revealed inside that member's own window: start minus their start
  # offset to stop plus their extra time (seconds via DATE_ADD/DATE_SUB, never
  # ADDTIME). Same columns and grouping as hint_reveal_for_problems.
  scope :hint_reveal_in_contest_windows, ->(contest, problems) {
    Comment.joins(:comment_reveals)
      .joins("JOIN contests_users hint_cu ON hint_cu.user_id = comment_reveals.user_id " \
             "AND hint_cu.contest_id = #{contest.id.to_i}")
      .where(commentable: problems, commentable_type: 'Problem')
      .where('comment_reveals.created_at >= DATE_SUB(?, INTERVAL IFNULL(hint_cu.start_offset_second, 0) SECOND)', contest.start)
      .where('comment_reveals.created_at <= DATE_ADD(?, INTERVAL IFNULL(hint_cu.extra_time_second, 0) SECOND)', contest.stop)
      .group('comment_reveals.user_id', :commentable_id)
  }

  scope :hints, -> { where(kind: HINT_KIND.keys) }

  scope :llm_assists_for_submissions, ->(submissions) {
    Comment.where(commentable: submissions, commentable_type: 'Submission').group(:commentable_id)
  }

  # AI-assist requests made on `submissions` (a relation), attributed to the
  # submission — i.e. to the student who is charged — not to whoever pressed
  # Get (an admin may ask on a student's behalf; `chargeable_for` above counts
  # by requester instead).
  scope :llm_assists_on, ->(submissions) {
    where(kind: 'llm_assist', commentable_type: 'Submission', commentable_id: submissions.select(:id))
  }

  # A contest comment (staff notes on a contest, design 2026-11-18) is body
  # only: author + time + text.
  validates :title, presence: true, unless: -> { commentable_type == 'Contest' }
  validates :body, presence: true, if: -> { commentable_type == 'Contest' }

  # One row of `usage_by_model`.
  UsageRow = Struct.new(:model, :requests, :answered, :points, :dollars, :priced, :prompt_tokens, :completion_tokens,
                        keyword_init: true)

  # Per-model roll-up over the receiver (an llm_assist scope): requests made,
  # answers (status ok), points charged, the provider's own dollar figure and
  # how many rows carried one (providers without a cost source leave llm_cost
  # nil — the Genie relay, and every row before 2026-09-03), tokens in / out.
  # Heaviest model first. Rendered by comments/_llm_usage_by_model.
  def self.usage_by_model
    unscope(:order).group(:llm_model).order(Arel.sql('COUNT(*) DESC'), :llm_model)
      .pluck(:llm_model,
             Arel.sql('COUNT(*)'),
             Arel.sql("SUM(comments.status = #{statuses[:ok]})"),
             Arel.sql('COALESCE(SUM(comments.cost), 0)'),
             Arel.sql('SUM(comments.llm_cost)'),
             Arel.sql('COUNT(comments.llm_cost)'),
             Arel.sql('SUM(comments.prompt_tokens)'),
             Arel.sql('SUM(comments.completion_tokens)'))
      .map do |model, requests, answered, points, dollars, priced, prompt_tokens, completion_tokens|
        UsageRow.new(model: model, requests: requests, answered: answered.to_i, points: points.to_f,
                     dollars: dollars, priced: priced, prompt_tokens: prompt_tokens, completion_tokens: completion_tokens)
      end
  end

  def to_label
    "#{kind}: #{title}"
  end

  # check if the user can acquire this comment
  # This check both the logic of commentable, the contest, and the user itself
  def acquirable_by?(user)
    # basic user logic
    return false unless user.present? && user.enabled?

    # call the specific model logic
    commentable.comment_reveal_prerequisite_satisfied?(self, user)
  end

  # Token counts live inside the raw provider response we already store
  # (`llm_response`); copy them onto the columns. Used by
  # `rake comments:backfill_llm_usage` for rows written before the columns
  # existed. The dollar figure came from a response header and is not
  # recoverable, so `llm_cost` is left alone. Returns true when written.
  def backfill_llm_usage!
    parsed = JSON.parse(llm_response.to_s)
    usage = parsed.is_a?(Hash) ? parsed['usage'] : nil
    return false unless usage.is_a?(Hash)
    update_columns(prompt_tokens: usage['prompt_tokens'], completion_tokens: usage['completion_tokens'])
    true
  rescue JSON::ParserError
    false
  end

  def self.cost_summary_for(user, contest)
    comments = chargeable_for(user, (contest.start)..(contest.stop))
    {
      count: comments.count,
      total_cost: comments.sum(:cost)
    }
  end

  # automatically set the title to "Hint xxx"
  def set_default_hint_title
    return if title.present?

    # Find the highest existing hint number for the same problem
    scope = Comment.where(commentable: self.commentable).where("title LIKE ?", "Hint %")

    # The SQL fragment extracts the number after "Hint " and converts it to an integer.
    last_hint_number = scope.maximum("CAST(SUBSTRING(title FROM 6) AS UNSIGNED)")

    # Calculate the next number. If no hints exist, it defaults to 0 + 1 = 1.
    next_number = (last_hint_number || 0) + 1

    self.title = "Hint #{next_number}"
  end
end
