class Submission < ApplicationRecord
  enum :tag, {default: 0, model: 1}, prefix: true
  enum :status, {submitted: 0, evaluating: 1, done: 2, compilation_error: 3, compilation_success: 4, grader_error: 5}


  belongs_to :language
  belongs_to :problem
  belongs_to :user

  has_many :evaluations, dependent: :destroy

  # viva exam
  has_many :viva_turns, -> { order(:sequence) }, dependent: :destroy
  has_one :viva_grade, dependent: :destroy

  # comments
  has_many :comments, as: :commentable, dependent: :destroy
  # Allows you to get all comment reveals for comments belonging to this submission
  has_many :comment_reveals, through: :comments


  before_validation :assign_language
  before_save :assign_latest_number_if_new_recond

  validates_length_of :source, maximum: 1_000_000, allow_blank: true, message: 'code too long, the limit is 1,000,000 bytes'
  validate :must_have_valid_problem
  validate :must_specify_language

  has_one :task

  has_many_attached :compiled_files

  scope :by_id_range, ->(from, to) {
    query = all
    query = query.where('submissions.id >= ?', from) if from.present?
    query = query.where('submissions.id <= ?', to) if to.present?
    query
  }

  scope :by_submitted_at, ->(from, to) {
    query = all
    query = query.where('submissions.submitted_at >= ?', from) if from.present?
    query = query.where('submissions.submitted_at <= ?', to) if to.present?
    query
  }

  scope :with_llm_stat_by_problem, ->  {
    joins(:comments)
      .where('comments.kind': 'llm_assist')
      .group(:problem_id)
      .select('problem_id', 'count(comments.id) as count', 'sum(comments.cost) as cost')
  }

  # this is a large one used for buildling data for _score_table and datatables/init_score_table_controller.js
  # the final result should be processed further by Submission.calculate_max_score
  scope :max_score_report, ->(problems, start, stop) {
    max_records = all
      .group('submissions.user_id,submissions.problem_id')
      .select('MAX(submissions.points) as max_score, submissions.user_id, submissions.problem_id')

    llm_assist_count = Comment.llm_assists_for_submissions(all)
      .select('SUM(comments.cost) as llm_cost')
      .select('COUNT(comments.id) as llm_count')
      .select('comments.commentable_id as submission_id')

    # should I includes all hint? or just hint reveal during the given time?
    hint_reveal = Comment.hint_reveal_for_problems(problems, start..stop)
      .select('comment_reveals.user_id as user_id')
      .select('comments.commentable_id as problem_id')
      .select('SUM(comments.cost) as hint_cost')
      .select('count(comments.id) as hint_count')

    # records having the same score as the max record
    # this is what we returned
    all.joins(:user)
      .joins("JOIN (#{max_records.to_sql}) MAX_RECORD ON " +
                   'submissions.points = MAX_RECORD.max_score AND ' +
                   'submissions.user_id = MAX_RECORD.user_id AND ' +
                   'submissions.problem_id = MAX_RECORD.problem_id ')
      .joins("LEFT JOIN (#{llm_assist_count.to_sql}) LLM_ASSIST ON " +
        "submissions.id = LLM_ASSIST.submission_id"
       )
      .joins("LEFT JOIN (#{hint_reveal.to_sql}) HINT_REVEAL ON " +
        "submissions.user_id = HINT_REVEAL.user_id AND " +
        "submissions.problem_id = HINT_REVEAL.problem_id "
       )
      .joins(:problem)
      .select('submissions.user_id,users.login,users.full_name,users.remark')
      .select('problems.name')
      .select('max_score')
      .select('LEAST(max_score,100.0-IFNULL(LLM_ASSIST.llm_cost,0.0)-IFNULL(HINT_REVEAL.hint_cost,0.0)) as final_score')
      .select('submitted_at')
      .select('submissions.id as sub_id')
      .select('submissions.problem_id,submissions.user_id')
      .select('LLM_ASSIST.llm_cost, LLM_ASSIST.llm_count')
      .select('HINT_REVEAL.hint_cost, HINT_REVEAL.hint_count')
  }


  def add_judge_job(dataset = problem.live_dataset, priority = 0)
    evaluations.delete_all
    self.update(status: 'submitted', points: nil, grader_comment: nil, graded_at: nil)
    Job.add_grade_submission_job(self, dataset, priority)
  end

  # nil viva_archived_at means this is the canonical/active viva submission
  # for its (user, problem); a non-nil timestamp means an admin has set the
  # submission aside so a fresh viva can be started. Non-viva submissions
  # leave viva_archived_at nil forever — the column is meaningful only for
  # viva problems.
  def viva_archived?
    viva_archived_at.present?
  end


  def set_grading_complete(point, grading_text, max_time, max_mem)
    update(points: point, status: :done, graded_at: Time.zone.now, grader_comment: grading_text, max_runtime: max_time, peak_memory: max_mem)
  end

  def set_grading_error(error_text)
    update(points: 0, status: :grader_error, graded_at: Time.zone.now, grader_comment: error_text)
  end


  def self.find_last_by_user_and_problem(user_id, problem_id)
    where("user_id = ? AND problem_id = ?", user_id, problem_id).last
  end

  def self.find_all_last_by_problem(problem_id)
    # need to put in SQL command, maybe there's a better way
    Submission.includes(:user).find_by_sql("SELECT * FROM submissions " +
      "WHERE id = " +
        "(SELECT MAX(id) FROM submissions AS subs " +
      "WHERE subs.user_id = submissions.user_id AND " +
        "problem_id = " + problem_id.to_s + " " +
      "GROUP BY user_id) " +
      "ORDER BY user_id")
  end

  def revealed_comments_for_user(user)
    comments.joins(:comment_reveals).where(comment_reveals: { user_id: user.id })
  end


  def self.find_last_for_all_available_problems(user_id)
    submissions = Array.new
    problems = Problem.available
    problems.each do |problem|
      sub = Submission.find_last_by_user_and_problem(user_id, problem.id)
      submissions << sub if sub!=nil
    end
    submissions
  end

  def download_filename
    if self.problem.output_only
      return "#{self.problem.name}-#{self.user.login}-#{self.id}.#{Pathname.new(self.source_filename).extname}"
    else
      if self.language.binary?
        # for binary language (such as archive), we extract the extension from the source filename
        return "#{self.problem.name}-#{self.user.login}-#{self.id}#{Pathname.new(self.source_filename).extname rescue ''}"
      else
        return "#{self.problem.name}-#{self.user.login}-#{self.id}.#{self.language.ext}"
      end
    end
  end

  def has_processing_comments?
    comments.where(status: 'processing').any?
  end

  #
  # ---- service ----
  #

  # records should be a submissions record WITH MAX SCORE only
  #   and it should have following additional columns: sub_id, login, max_score,
  # return  a hash {score: xx, stat: yy}
  # xx is {
  #   #{user.login}: {
  #     id:, full_name:, remark:,
  #     raw_#{prob.id}:        # score
  #     time_#{prob.id}:       # the latest time of that score
  #     sub_#{prob.id}:        # the sub_id of that score
  #     deduction_#{prob.id}:  # the sub_id of that score
  #     final_#{prob.id}:      # the sub_id of that score
  #     ...
  # }
  def self.calculate_max_score(records, users, problems, with_comments: true)
    result = {score: Hash.new { |h, k| h[k] = {} },
              stat: Hash.new { |h, k| h[k] = { zero: 0, partial: 0, full: 0, sum: 0, sum_deduced: 0, score: [] } } }

    # build users
    users.each do |u|
      result[:score][u.login]['id'] = u.id
      result[:score][u.login]['full_name'] = u.full_name
      result[:score][u.login]['remark'] = u.remark
    end


    # iterates each sub and extract
    #   max score
    #   id and time of last submission with that max score
    #   cost of llm, count of llm
    records.each do |sub|
      result[:score][sub.login]["raw_score_#{sub.problem_id}"] = sub.max_score || 0

      # we pick the latest and save all related info
      unless (result[:score][sub.login]["time_#{sub.problem_id}"] || Date.new) > sub.submitted_at
        result[:score][sub.login]["time_#{sub.problem_id}"] = sub.submitted_at
        result[:score][sub.login]["sub_#{sub.problem_id}"] = sub.sub_id
        if with_comments
          result[:score][sub.login]["llm_count_#{sub.problem_id}"] = sub.llm_count
          result[:score][sub.login]["llm_cost_#{sub.problem_id}"] = sub.llm_cost
          result[:score][sub.login]["hint_count_#{sub.problem_id}"] = sub.hint_count
          result[:score][sub.login]["hint_cost_#{sub.problem_id}"] = sub.hint_cost
          result[:score][sub.login]["final_score_#{sub.problem_id}"] = sub.final_score.to_d

          result[:score][sub.login]["total_cost_#{sub.problem_id}"] = nil
          result[:score][sub.login]["total_cost_#{sub.problem_id}"] = 0.to_d + (sub.llm_cost || 0.0) + (sub.hint_cost || 0.0) unless sub.llm_cost.nil? && sub.hint_cost.nil?
        end
      end
    end

    return result
  end

  # deprecated
  def self.find_by_user_problem_number(user_id, problem_id, number)
    where("user_id = ? AND problem_id = ? AND number = ?", user_id, problem_id, number).first
  end


  protected

  def self.find_option_in_source(option, source)
    if source==nil
      return nil
    end
    i = 0
    source.each_line do |s|
      if s =~ option
        words = s.split
        return words[1]
      end
      i = i + 1
      if i==10
        return nil
      end
    end
    return nil
  end

  def self.find_language_in_source(source, source_filename = "")
    langopt = find_option_in_source(/^LANG:/, source)
    if langopt
      return (Language.find_by_name(langopt) ||
              Language.find_by_pretty_name(langopt))
    else
      if source_filename
        return Language.find_by_extension(source_filename.split('.').last)
      else
        return nil
      end
    end
  end

  def self.find_problem_in_source(source, source_filename = "")
    prob_opt = find_option_in_source(/^TASK:/, source)
    if problem = Problem.find_by_name(prob_opt)
      return problem
    else
      if source_filename
        return Problem.find_by_name(source_filename.split('.').first)
      else
        return nil
      end
    end
  end


  def assign_language
    # viva submissions carry a sentinel language; skip code-specific language detection
    return if self.problem&.viva_exam?

    if self.language == nil
      # detect from filename
      self.language = Submission.find_language_in_source(self.source,
                                                         self.source_filename)

    end

    # if problem permit only one language, we always use that one
    # even when the problem already have one
    permitted_lang_ids = self.problem.get_permitted_lang_as_ids
    if permitted_lang_ids.count == 1
      self.language_id = permitted_lang_ids[0]
    end
  end

  # validation codes
  def must_specify_language
    return if self.source==nil

    # for output_only tasks
    return if self.problem!=nil and self.problem.output_only

    if self.language == nil
      errors.add(:source, :invalid, message: "Cannot detect language. Did you submit a correct source file?")
    end
  end

  def must_have_valid_problem
    return if self.source==nil
    if self.problem==nil
      errors.add(:problem, :blank, 'aaa')
    else
      # admin always have right
      return if self.user.admin?

      # check if user has the right to submit the problem
      errors[:base] << "Authorization error: you have no right to submit to this problem" if (!self.user.problems_for_action(:submit).include?(self.problem)) and (self.new_record?)
    end
  end

  # callbacks
  def assign_latest_number_if_new_recond
    return if !self.new_record?
    latest = Submission.find_last_by_user_and_problem(self.user_id, self.problem_id)
    self.number = (latest==nil) ? 1 : latest.number + 1
  end

  public
end
