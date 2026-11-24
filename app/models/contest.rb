class Contest < ApplicationRecord
  include Auditable
  audited only: %i[name enabled description start stop finalized
                   pre_contest_seconds post_contest_seconds allow_hint outside_login_off
                   deduction_cap assist_spending_limit]

  has_many :contests_problems, class_name: 'ContestProblem', dependent: :destroy
  has_many :contests_users, class_name: 'ContestUser', dependent: :destroy
  has_many :problems, through: :contests_problems
  has_many :users, through: :contests_users

  # Staff notes on the contest (issues to resolve, after-action report): kind
  # `comment` rows, seen only on the manage page.
  has_many :comments, as: :commentable, dependent: :destroy

  scope :enabled, -> { where(enabled: true) }
  # scope :active, -> (time = Time.zone.now) { where(enabled: true).where('start <= ? and stop >= ?',time,time)}


  scope :editable_by_user, ->(user_id) {
    joins(:contests_users).where(contests_users: { user_id: user_id, enabled: true, role: 'editor' })
  }

  scope :submittable_by_user, ->(user_id) {
    joins(:contests_users).where(contests_users: { user_id: user_id, enabled: true })
  }

  # When the outside-login block of this contest ends for the last student:
  # stop plus the longest student extra time. nil without a stop.
  # Disabled rows count toward the longest extra time on purpose (enabled flags
  # are ignored here, spec Part 1).
  def outside_login_block_ends_at
    return nil if stop.nil?
    stop + (contests_users.user.maximum(:extra_time_second) || 0).seconds
  end

  # new_users are active record relation
  # return a toast reaponse hash

  # need pluralize helper function
  delegate :pluralize, to: 'ActionController::Base.helpers'

  # validates the name, (also using custom validator)
  validates :name, presence: true, uniqueness: true, name_format: true
  validate :outside_login_off_needs_stop
  # Help-deduction settings (spec 2026-11-21): blank = no cap / the site's
  # spending limit.
  validates :deduction_cap, numericality: { only_integer: true, in: 0..HelpDeduction::FULL_SCORE }, allow_nil: true
  validates :assist_spending_limit, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  AddResult = Struct.new(:added, :skipped, :status, :model)

  def add_users(new_users, role: 'user')
    return AddResult.new(added: 0, skipped: 0) if new_users.blank?

    # remove already existing users
    requested_user_ids = new_users.pluck(:id)
    user_ids_to_add = requested_user_ids - self.user_ids

    num_added = user_ids_to_add.count
    num_skipped = requested_user_ids.count - num_added

    user_ids_to_add.each do |user_id|
      self.contests_users.build(user_id: user_id, role: role)
    end
    return AddResult.new(added: num_added, skipped: num_skipped)
  end

  def add_users_from_csv(lines)
    error_logins = []
    first_error = nil
    added_users = []

    lines.split("\n").each do |line|
      # split with large limit, this will cause consecutive ',' to be result in a blank instead of nil
      items = line.chomp.split(',', 1000)

      login = items[0]
      seat = items.length >= 2 ? items[1] : nil
      remark = items.length >= 3 ? items[2] : nil

      user = User.where(login: login).first

      unless user
        error_logins << "'#{login}'"
        next
      end

      cu = self.contests_users.find_or_create_by(user: user)

      cu.remark = remark if remark
      cu.seat = seat if seat

      if cu.save
        added_users << user
      else
        error_logins << "'#{login}'"
        first_error = user.errors.full_messages.to_sentence unless first_error
      end
    end

    return {error_logins: error_logins, first_error: first_error, added_users:  added_users}
  end

  def add_problems_and_assign_number(new_problems)
    return AddResult.new(added: 0, skipped: 0) if new_problems.blank?

    # remove already existing problems
    requested_problem_ids = new_problems.pluck(:id)
    problem_ids_to_add = requested_problem_ids - self.problem_ids

    num_added = problem_ids_to_add.count
    num_skipped = requested_problem_ids.count - num_added


    latest_num = (self.contests_problems.maximum(:number) || 0) + 1
    problem_ids_to_add.each do |new_prob_id|
      self.contests_problems.build(problem_id: new_prob_id, number: latest_num)
      latest_num += 1
    end

    return AddResult.new(added: num_added, skipped: num_skipped)
  end

  # contest problems as students and editors see them: by number, ties/blanks by id
  def problems_in_display_order
    contests_problems.includes(:problem).reorder('contests_problems.number', 'contests_problems.id').to_a
  end

  # Write numbers 1..n following problem_ids. Ids outside the contest and
  # repeated ids are ignored; contest problems not mentioned are appended in
  # their current display order. Returns the final problem-id order.
  def reorder_problems!(problem_ids)
    current = problems_in_display_order
    by_pid = current.index_by(&:problem_id)
    wanted = Array(problem_ids).map { |i| i.to_s =~ /\A\d+\z/ ? i.to_i : nil }.compact
    ordered = wanted.select { |i| by_pid.key?(i) }.uniq
    ordered += current.map(&:problem_id) - ordered
    transaction do
      ordered.each_with_index do |pid, idx|
        cp = by_pid[pid]
        cp.update!(number: idx + 1) if cp.number != idx + 1
      end
    end
    ordered
  end

  # swap the problem with its neighbour in display order (:up / :down), then renumber 1..n
  # returns the new 1-based position, nil if the problem is not in this contest
  def move_problem(problem, direction)
    ids = problems_in_display_order.map(&:problem_id)
    idx = ids.index(problem.id)
    return nil if idx.nil?
    other = direction == :up ? idx - 1 : idx + 1
    if other >= 0 && other < ids.size
      ids[idx], ids[other] = ids[other], ids[idx]
    end
    reorder_problems!(ids).index(problem.id) + 1
  end

  # return :later, :pre, :during, :post, :ended
  def contest_status
    current_time = Time.zone.now
    return :ended if current_time > self.stop
    return :later if current_time < self.start
    return :during
  end

  def get_next_name(base = self.name)
    num = 0
    name = base
    while Contest.where(name: name).count > 0
      num += 1
      name = base + "_#{num}"
    end
    return name
  end

  # check in interval in seconds
  def self.check_in_interval
    # once every minutes
    return 60
  end

  # return a submissions of this contests
  # this includes extra_time_second and start_offset_second as well
  def submissions
    Submission.regular.joins(user: :contests_users)
      .where('contest_id = ?', self.id)
      .where(user: users, problem: problems)
      .where('submitted_at >= DATE_SUB(?,INTERVAL start_offset_second SECOND)', start)
      .where('submitted_at <= DATE_ADD(?,INTERVAL extra_time_second SECOND)', stop)
  end

  def user_submissions(user)
    cu = contests_users.where(user: user).take
    actual_start = start - cu.start_offset_second.second
    actual_stop = stop + cu.extra_time_second.second
    Submission.regular.where(user: user, problem: problems)
      .where('submitted_at >= ?', actual_start)
      .where('submitted_at <= ?', actual_stop)
  end

  # Open viva sessions of this contest: still :submitted, not archived, on
  # this contest's viva problems, by enrolled users, started inside the
  # window (with each user's start offset / extra time) — the same membership
  # and window rules as #submissions.
  def open_viva_sessions
    submissions.submitted.where(viva_archived_at: nil)
               .joins(:problem).merge(Problem.viva_exam)
  end

  # Viva grading status for the status line next to "Finish open vivas":
  # sessions whose interview has ended and whose first grade has not landed
  # (:evaluating), and sessions whose first grading failed (:grader_error),
  # over the same sessions as #open_viva_sessions (enrolled users, this
  # contest's viva problems, started inside the window, not archived).
  # Regrades of graded sessions stay :done and are not counted: those
  # students keep a valid grade the whole time. Zero and zero means the
  # contest's viva scores are final. Returns {grading:, errors:}.
  def viva_grading_counts
    counts = submissions.where(viva_archived_at: nil, status: %i[evaluating grader_error])
                        .joins(:problem).merge(Problem.viva_exam)
                        .reorder(nil).group(:status).count
    {grading: counts['evaluating'].to_i, errors: counts['grader_error'].to_i}
  end

  # "Finish open vivas" (contests/show): runs Submission#finalize_open_viva!
  # once over every open session — answered ones go to grading, greeting-only
  # ones are archived, a session whose assistant reply is still in flight is
  # skipped and reported so staff can click again shortly. Decided 2026-09-17
  # as a batch button rather than a contest-stop trigger; the manual precursor
  # of Phase B's window-end force-finish (doc/Viva-Exam.md). The 24 h reaper
  # stays as the safety net. Returns {graded:, archived:, skipped:}.
  def finish_open_vivas!(now: Time.zone.now)
    counts = {graded: 0, archived: 0, skipped: 0}
    open_viva_sessions.find_each do |sub|
      counts[sub.finalize_open_viva!(
        graded_note:   '(session closed by contest staff — grading begins)',
        archived_note: '(session closed by contest staff — archived)',
        now: now)] += 1
    end
    counts
  end

  #
  # -------- report ---------------
  #
  # This is for reporting the maximum score of each problem of each user
  # The Watch page's score table (contests#view_query). `users:` and
  # `problems:` narrow it — a contest-scoped Report page passes the subsets
  # its viewer may report on — and default to every member and every contest
  # problem, so the Watch page itself is unchanged.
  def score_report(users: self.users, problems: self.problems)
    subs = submissions.where(user: users, problem: problems)

    # calculate submission with max score
    max_records = subs
      .group('submissions.user_id,submissions.problem_id')
      .select('MAX(submissions.points) as max_score, submissions.user_id, submissions.problem_id')

    llm_assist_count = subs.joins(:comments).group(:user_id, :problem_id)
      .select('SUM(comments.cost) as llm_cost')
      .select('COUNT(comments.id) as llm_count')
      .select('user_id', 'problem_id')

    # each student's own window, start offset and extra time included
    hint_reveal = Comment.hint_reveal_in_contest_windows(self, problems)
      .select('comment_reveals.user_id as user_id')
      .select('comments.commentable_id as problem_id')
      .select('SUM(comments.cost) as hint_cost')
      .select('count(comments.id) as hint_count')

    # records having the same score as the max record
    records = subs
      .joins("JOIN (#{max_records.to_sql}) MAX_RECORD ON " +
                   'submissions.points = MAX_RECORD.max_score AND ' +
                   'submissions.user_id = MAX_RECORD.user_id AND ' +
                   'submissions.problem_id = MAX_RECORD.problem_id ')
      .joins("LEFT JOIN (#{llm_assist_count.to_sql}) LLM_ASSIST ON " +
        "submissions.user_id = LLM_ASSIST.user_id AND " +
        "submissions.problem_id = LLM_ASSIST.problem_id"
       )
      .joins("LEFT JOIN (#{hint_reveal.to_sql}) HINT_REVEAL ON " +
        "submissions.user_id = HINT_REVEAL.user_id AND " +
        "submissions.problem_id = HINT_REVEAL.problem_id "
       )
      .joins(:problem)
      .select('submissions.user_id,users_submissions.login,users_submissions.full_name,users_submissions.remark')
      .select('problems.name')
      .select('max_score')
      .select('submitted_at')
      .select('submissions.id as sub_id')
      .select('submissions.problem_id,submissions.user_id')
      .select('LLM_ASSIST.llm_cost, LLM_ASSIST.llm_count')
      .select('HINT_REVEAL.hint_cost, HINT_REVEAL.hint_count')


    return Submission.calculate_max_score(records, users, problems, deduction_cap: deduction_cap)
  end

  # The members a scoreboard or a contest-scoped report is about: the
  # contests_users rows with role `user` (editors are staff), enabled or
  # not — exactly the rows the Watch page lists (contests#view_query).
  def students
    User.where(id: contests_users.where(role: :user).select(:user_id))
  end

  # True when some member has a start offset or extra time, i.e. the
  # window differs per student (Contest#submissions applies it per row).
  def per_user_windows?
    contests_users.where('start_offset_second > 0 OR extra_time_second > 0').exists?
  end

  private

  def outside_login_off_needs_stop
    errors.add(:outside_login_off, 'needs a Stop time') if outside_login_off? && stop.nil?
  end
end
