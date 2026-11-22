# The help-deduction rule (spec
# docs/superpowers/specs/2026-11-21-deduction-cap-spending-limit-design.md).
#
# A revealed hint and an AI-help request each lower a problem's full score by
# their cost. Two numbers bound that, one name each:
#
# - deduction cap   — the most hints + AI help together can take off one
#                     problem's full score (Contest#deduction_cap; nil = none).
#                     A grade rule.
# - spending limit  — the most points of AI help a student can spend on one
#                     problem before further requests are refused (raw points,
#                     cap ignored; hints never counted). Contest
#                     #assist_spending_limit, nil = the site setting
#                     system.llm_assist_spending_limit (default 100).
#
# Every score, deduction, confirm box and refusal goes through this module so
# the rule exists once.
module HelpDeduction
  FULL_SCORE = 100
  SPENDING_LIMIT_KEY = 'system.llm_assist_spending_limit'.freeze
  DEFAULT_SPENDING_LIMIT = 100

  # What a problem's help costs once the cap applies.
  Budget = Struct.new(:cap, :contest_name, :hint_lost, :ai_lost, :ai_spent, :spending_limit, keyword_init: true) do
    def lost = hint_lost.to_f + ai_lost.to_f
    def counted = HelpDeduction.deduction(hint_lost, ai_lost, cap)
    # How much of a new charge of `cost` would count toward the deduction.
    def counts(cost) = cap.nil? ? cost.to_f : [[cap - counted, 0].max, cost.to_f].min
    def at_cap? = !cap.nil? && counted >= cap
  end

  module_function

  # The points counted against the full score: hints + AI help, up to `cap`.
  def deduction(hint, ai, cap)
    raw = hint.to_f + ai.to_f
    cap.nil? ? raw : [raw, cap.to_f].min
  end

  # The score that counts: the raw best score under the reduced full score,
  # never below 0 (a student can buy more help than a problem is worth).
  def final_score(raw_score, hint, ai, cap)
    [0.0, [raw_score.to_f, FULL_SCORE - deduction(hint, ai, cap)].min].max
  end

  # The global Best Score box: a whole number 0..100, anything else no cap.
  def parse_cap(value)
    v = Integer(value.to_s.strip, 10)
    v.between?(0, FULL_SCORE) ? v : nil
  rescue ArgumentError, TypeError
    nil
  end

  def site_spending_limit
    v = GraderConfiguration[SPENDING_LIMIT_KEY]
    v.nil? ? DEFAULT_SPENDING_LIMIT : v.to_i
  end

  # { problem_id => [Contest, ...] }: the user's running contests
  # (User#active_contests — own window, contest mode only) that include each
  # problem, where the user's membership is enabled (as the problem list
  # requires). One query; {} outside contest mode.
  def running_contests_by_problem(user, problem_ids)
    return {} if problem_ids.blank?

    user.active_contests
        .where(contests_users: { enabled: true })
        .joins(:contests_problems)
        .where(contests_problems: { problem_id: problem_ids, enabled: true })
        .select('contests_problems.problem_id AS cp_problem_id')
        .group_by(&:cp_problem_id)
  end

  # The cap of a problem's running contests: their one shared value, else nil
  # (none set, or they disagree — the list then shows a notice instead).
  def cap_for(contests)
    caps = contests.map(&:deduction_cap).uniq
    caps.size == 1 ? caps.first : nil
  end

  def caps_disagree?(contests)
    contests.map(&:deduction_cap).uniq.size > 1
  end

  # The largest of the running contests' limits, a blank one counting as the
  # site setting; the site setting when there is no running contest. Being
  # refused is what students complain about, so the largest wins.
  def spending_limit_for(contests)
    site = site_spending_limit
    contests.map { |c| c.assist_spending_limit || site }.max || site
  end

  # Normal mode's notice: problems in an enabled contest of the user's that
  # sets a cap. One query.
  def capped_problem_ids(user, problem_ids)
    return Set.new if problem_ids.blank?

    ContestProblem.joins(contest: :contests_users)
                  .where(problem_id: problem_ids, contests: { enabled: true }, contests_users: { user_id: user.id })
                  .where.not(contests: { deduction_cap: nil })
                  .distinct.pluck(:problem_id).to_set
  end

  # What the user has lost so far, per problem — the numbers the problem list
  # and the confirm boxes show. In contest mode only help inside the user's
  # running-contest window counts (hints by reveal time, AI help by the time
  # of the submission it was asked on). Two queries; pass `range:` when the
  # caller already has the window (the problem list does) to skip a third.
  # { problem_id => {hint_count:, hint_cost:, ai_count:, ai_cost:} }
  def losses(user, problem_ids, range: contest_window(user))
    out = Hash.new { |h, k| h[k] = { hint_count: nil, hint_cost: 0, ai_count: nil, ai_cost: 0 } }
    return out if problem_ids.blank?

    subs = Submission.regular.where(user: user, problem_id: problem_ids)
    subs = subs.where(submitted_at: range) if range
    subs.with_llm_stat_by_problem.each do |row|
      out[row.problem_id].merge!(ai_count: row.count, ai_cost: row.cost || 0)
    end

    reveals = { user: user }
    reveals[:created_at] = range if range
    Problem.joins(comments: :comment_reveals)
           .where(id: problem_ids, comment_reveals: reveals)
           .group(:id)
           .select('problems.id', 'count(comments.id) as count', 'sum(comments.cost) as cost')
           .each { |row| out[row.id].merge!(hint_count: row.count, hint_cost: row.cost || 0) }
    out
  end

  # The window help counts in: the union of the user's running contests'
  # own windows in contest mode (User#active_contests_range), else nil (all).
  def contest_window(user)
    GraderConfiguration.contest_mode? ? user.active_contests_range : nil
  end

  # Every point of AI help the user has been charged on the problem, ever —
  # what the spending limit counts.
  def ai_spent(user, problem_id)
    Comment.where(kind: 'llm_assist', status: 'ok', commentable_type: 'Submission')
           .where(commentable_id: Submission.where(user_id: user.id, problem_id: problem_id).select(:id))
           .sum(:cost)
  end

  # The confirm boxes' numbers for one user and problem.
  def budget(user, problem)
    contests = running_contests_by_problem(user, [problem.id])[problem.id] || []
    cap = cap_for(contests)
    lost = losses(user, [problem.id])[problem.id]
    Budget.new(cap: cap, contest_name: (contests.first.name if cap),
               hint_lost: lost[:hint_cost], ai_lost: lost[:ai_cost],
               ai_spent: ai_spent(user, problem.id), spending_limit: spending_limit_for(contests))
  end
end
