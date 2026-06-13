class Contest < ApplicationRecord
  include Auditable
  audited only: %i[name enabled description start stop finalized
                   pre_contest_seconds post_contest_seconds allow_hint]

  has_many :contests_problems, class_name: 'ContestProblem', dependent: :destroy
  has_many :contests_users, class_name: 'ContestUser', dependent: :destroy
  has_many :problems, through: :contests_problems
  has_many :users, through: :contests_users

  scope :enabled, -> { where(enabled: true) }
  # scope :active, -> (time = Time.zone.now) { where(enabled: true).where('start <= ? and stop >= ?',time,time)}


  scope :editable_by_user, ->(user_id) {
    joins(:contests_users).where(contests_users: { user_id: user_id, enabled: true, role: 'editor' })
  }

  scope :submittable_by_user, ->(user_id) {
    joins(:contests_users).where(contests_users: { user_id: user_id, enabled: true })
  }

  # new_users are active record relation
  # return a toast reaponse hash

  # need pluralize helper function
  delegate :pluralize, to: 'ActionController::Base.helpers'

  # validates the name, (also using custom validator)
  validates :name, presence: true, uniqueness: true, name_format: true

  AddResult = Struct.new(:added, :skipped, :status, :model)

  # return an ActiveRecord relation of users that is submittable for this con
  def submittable_users(current_time = Time.zone.now)
    return User.none unless enabled?
    user_ids = contests_users.where(enabled: true).where('IFNULL(extra_time_second) >= ?', current_time - self.stop).pluck :user_id
    Users.where(id: user_ids, enabled: true)
  end

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


    latest_num = self.contests_problems.maximum(:number) || 1
    problem_ids_to_add.each do |new_prob_id|
      self.contests_problems.build(problem_id: new_prob_id, number: latest_num)
      latest_num += 1
    end

    return AddResult.new(added: num_added, skipped: num_skipped)
  end

  # set the number of the problem to *number* and rearrage other
  def set_problem_number(problem, number)
    num = 1
    self.contests_problems.where.not(problem_id: problem.id).order(:number).each do |cp, idx|
      offset = (num) >= number ? 1 : 0
      cp.update(number: num+offset)
      num += 1
    end
    self.contests_problems.where(problem_id: problem.id).first.update(number: [self.contests_problems.count, [1, number.round].max].min)
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
    Submission.joins(user: :contests_users)
      .where('contest_id = ?', self.id)
      .where(user: users, problem: problems)
      .where('submitted_at >= DATE_SUB(?,INTERVAL start_offset_second SECOND)', start)
      .where('submitted_at <= DATE_ADD(?,INTERVAL extra_time_second SECOND)', stop)
  end

  def user_submissions(user)
    cu = contests_users.where(user: user).take
    actual_start = start - cu.start_offset_second.second
    actual_stop = stop + cu.extra_time_second.second
    Submission.where(user: user, problem: problems)
      .where('submitted_at >= ?', actual_start)
      .where('submitted_at <= ?', actual_stop)
  end

  #
  # -------- report ---------------
  #
  # This is for reporting the maximum score of each problem of each user
  def score_report
    # calculate submission with max score
    max_records = self.submissions
      .group('submissions.user_id,submissions.problem_id')
      .select('MAX(submissions.points) as max_score, submissions.user_id, submissions.problem_id')

    llm_assist_count = submissions.joins(:comments).group(:user_id, :problem_id)
      .select('SUM(comments.cost) as llm_cost')
      .select('COUNT(comments.id) as llm_count')
      .select('user_id', 'problem_id')

    hint_reveal = Comment.hint_reveal_for_problems(self.problems, (self.start)..(self.stop))
      .select('comment_reveals.user_id as user_id')
      .select('comments.commentable_id as problem_id')
      .select('SUM(comments.cost) as hint_cost')
      .select('count(comments.id) as hint_count')

    # records having the same score as the max record
    records = self.submissions
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
      .select('LEAST(max_score,100.0-IFNULL(LLM_ASSIST.llm_cost,0.0)-IFNULL(HINT_REVEAL.hint_cost,0.0)) as final_score')
      .select('submitted_at')
      .select('submissions.id as sub_id')
      .select('submissions.problem_id,submissions.user_id')
      .select('LLM_ASSIST.llm_cost, LLM_ASSIST.llm_count')
      .select('HINT_REVEAL.hint_cost, HINT_REVEAL.hint_count')


    return Submission.calculate_max_score(records, users, problems)
  end
end
