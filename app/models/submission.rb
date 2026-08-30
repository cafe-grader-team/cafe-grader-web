class Submission < ApplicationRecord
  enum :tag, {default: 0, model: 1}, prefix: true
  enum :status, {submitted: 0, evaluating: 1, done: 2, compilation_error: 3, compilation_success: 4, grader_error: 5}


  belongs_to :language
  belongs_to :problem
  belongs_to :user

  has_many :evaluations, dependent: :destroy

  belongs_to :repaired_from, class_name: 'Submission', optional: true
  has_many :repair_attempts, class_name: 'SubmissionRepair', foreign_key: :original_submission_id

  # viva exam
  has_many :viva_turns, -> { order(:sequence) }, dependent: :destroy
  has_one :viva_grade, dependent: :destroy

  # How long a viva submission may sit in :evaluating (grading in flight)
  # before fail_stale_viva_evaluating! treats it as abandoned — the worker
  # process was killed mid-call (deploy, crash, OOM) so neither the graceful
  # success path (handle_response) nor the graceful failure path
  # (Llm::VivaGradeAssistJob#on_retries_exhausted) ever ran to move the
  # submission out of :evaluating.
  #
  # Must sit safely ABOVE the worst-case span Llm::VivaGradeAssistJob's own
  # retry_on chain (Llm::RequestJob) can legitimately spend before it gives
  # up and flips the submission to :grader_error itself — otherwise this
  # sweeper would yank a submission out from under a job that's still
  # retrying normally. The longest of RequestJob's four retry_on handlers is
  # Faraday::TimeoutError (wait: :polynomially_longer, attempts: 3): each of
  # the 3 attempts can run up to Llm::Request.connection's 300s request
  # timeout before raising, and ActiveJob's polynomially_longer backoff
  # between attempts is (1**4)+2=3s then (2**4)+2=18s. Worst case:
  #   3 attempts * 300s  +  3s + 18s backoff  =  921s (~15.35 min)
  # 20 minutes leaves a ~4.5 minute margin above that, and doubles
  # VivaTurn::STALE_AFTER (10 min) as a round-number floor.
  STALE_EVALUATING_AFTER = 20.minutes

  # What a successful viva grading run writes into grader_comment. The LLM
  # narrative lives only in viva_grades.narrative (rendered by the grade card
  # on the viva page); grader_comment is a compact verdict field everywhere
  # else (main list, stat tables, Submission report, API last_result), so a
  # viva gets one of these short markers instead. Read viva_terminated_at?
  # for the flag itself — never parse this string.
  VIVA_RESULT_MARKER            = 'viva'.freeze
  VIVA_RESULT_TERMINATED_MARKER = 'viva:terminated'.freeze

  # Viva sessions with no turn activity for this long, still :submitted,
  # are finalized by reap_abandoned_vivas! (recurring, production only).
  ABANDONED_VIVA_REAP_AFTER = 24.hours

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

  # Near-Miss Grading: shadow submissions are machine-generated repaired
  # copies (repaired_from_id points at the original). Every student-visible
  # query and every quota count must read .regular; the judge worker, admin
  # monitoring, and number-assignment must NOT filter. See the exclusion
  # audit in docs/superpowers/plans/2026-07-30-near-miss-grading.md.
  scope :regular, -> { where(repaired_from_id: nil) }
  scope :shadow,  -> { where.not(repaired_from_id: nil) }

  # Viva submissions parked in :evaluating with no viva_grade row yet,
  # older than STALE_EVALUATING_AFTER — i.e. what
  # fail_stale_viva_evaluating! would sweep right now. A viva_grade row
  # already existing on an :evaluating submission means grading is
  # mid-write (handle_response persists the grade row before flipping
  # status to :done, see Llm::VivaGradeAssist#handle_response) — a
  # different bug if it lingers, and NOT something this scope or the
  # sweeper should touch.
  #
  # Used by GradersController to surface count + rows on the graders
  # "stuck" monitoring page, mirroring VivaTurn.stuck.
  scope :stale_evaluating, -> {
    evaluating
      .joins(:problem).merge(Problem.viva_exam)
      .where.missing(:viva_grade)
      .where("submissions.updated_at < ?", STALE_EVALUATING_AFTER.ago)
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


  def shadow? = repaired_from_id.present?

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

  # See VIVA_RESULT_MARKER. Shared by Llm::VivaGradeAssist (success path)
  # and Viva::GraderCommentCleaner (one-off rewrite of pre-marker rows).
  def viva_result_marker
    viva_terminated_at? ? VIVA_RESULT_TERMINATED_MARKER : VIVA_RESULT_MARKER
  end


  def set_grading_complete(point, grading_text, max_time, max_mem)
    update(points: point, status: :done, graded_at: Time.zone.now, grader_comment: grading_text, max_runtime: max_time, peak_memory: max_mem)
  end

  def set_grading_error(error_text)
    update(points: 0, status: :grader_error, graded_at: Time.zone.now, grader_comment: error_text)
  end

  # Marks any viva submission stuck in :evaluating (grading in flight, no
  # viva_grade row) for longer than `threshold` as :grader_error, so the
  # existing admin "Rejudge"/re-grade path (SubmissionsController#rejudge)
  # applies. Runs from the same Solid Queue recurring task as
  # VivaTurn.fail_stale! (see config/recurring.yml). Without this, a worker
  # process killed mid-grade-call (deploy, crash, OOM) — as opposed to a
  # graceful failure, which Llm::VivaGradeAssistJob#on_retries_exhausted
  # already handles — leaves the submission in :evaluating forever, and the
  # student sees "Grading in progress..." forever.
  def self.fail_stale_viva_evaluating!(threshold: STALE_EVALUATING_AFTER, now: Time.zone.now)
    stale = evaluating
              .joins(:problem).merge(Problem.viva_exam)
              .where.missing(:viva_grade)
              .where("submissions.updated_at < ?", now - threshold)
    count = 0
    stale.find_each do |sub|
      sub.update(
        status:         :grader_error,
        grader_comment: "Grading timed out (worker process likely crashed mid-call, no response after #{threshold.inspect}). Use Rejudge to try again."
      )
      count += 1
    end
    Rails.logger.info "Submission.fail_stale_viva_evaluating!: marked #{count} stuck viva submission(s) as :grader_error" if count.positive?
    count
  end

  # Finalizes viva sessions abandoned mid-interview. Grading fires only on
  # the done-sentinel, the hard cap, or the student's End button — a student
  # who closes the tab triggers none of them, so their session sat parked in
  # :submitted forever (2026-08-24 student trial: ~17 sessions with real
  # progress, plus ~27 greeting-only peeks). A session idle for `idle_for`
  # (no turn activity, status still :submitted, not archived):
  #   - with at least one student answer: finalized exactly like the
  #     hard-cap / End-button paths — system turn, :evaluating, grade job
  #     with no model: (the grade service default decides, rev 2011) — so
  #     the student gets a grade for what they showed;
  #   - greeting-only: archived (the restart flow's soft-hide). Under the
  #     engaged-only limit accounting (rev 2014) it never counted anyway.
  # Sessions with a :processing turn are skipped: VivaTurn.fail_stale!
  # owns stuck turns, and once it flips them to :error a later sweep here
  # picks the session up.
  # Registered production-only in config/recurring.yml — in development it
  # would silently spend LLM tokens grading forgotten local sessions.
  def self.reap_abandoned_vivas!(idle_for: ABANDONED_VIVA_REAP_AFTER, now: Time.zone.now)
    cutoff = now - idle_for
    stale = submitted
              .joins(:problem).merge(Problem.viva_exam)
              .where(viva_archived_at: nil)
              .where("submissions.submitted_at < ?", cutoff)
              .where.not(id: VivaTurn.where("updated_at >= ?", cutoff).select(:submission_id))
              .where.not(id: VivaTurn.where(status: :processing).select(:submission_id))
    graded = archived = 0
    stale.find_each do |sub|
      if sub.viva_turns.where(role: :student).exists?
        sub.viva_turns.create!(role: :system, status: :ok,
          content: '(session expired after inactivity — grading begins)')
        sub.update!(status: :evaluating)
        Llm::VivaGradeAssistJob.perform_later(sub)
        graded += 1
      else
        sub.viva_turns.create!(role: :system, status: :ok,
          content: '(session expired after inactivity — archived)')
        sub.update!(viva_archived_at: now)
        archived += 1
      end
    end
    Rails.logger.info "Submission.reap_abandoned_vivas!: graded #{graded}, archived #{archived} abandoned viva session(s)" if (graded + archived).positive?
    {graded: graded, archived: archived}
  end


  def self.find_last_by_user_and_problem(user_id, problem_id)
    regular.where("user_id = ? AND problem_id = ?", user_id, problem_id).last
  end

  def self.find_all_last_by_problem(problem_id)
    # need to put in SQL command, maybe there's a better way
    Submission.includes(:user).find_by_sql("SELECT * FROM submissions " +
      "WHERE id = " +
        "(SELECT MAX(id) FROM submissions AS subs " +
      "WHERE subs.user_id = submissions.user_id AND " +
        "problem_id = " + problem_id.to_s + " " +
        "AND repaired_from_id IS NULL " +
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
    regular.where("user_id = ? AND problem_id = ? AND number = ?", user_id, problem_id, number).first
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

  # Last line of defense behind the controller gates: the DB write itself
  # re-checks submit authorization via THE shared gate
  # (User#can_submit_to_problem? — also used by main#submit, the API create,
  # and viva start), so a future controller that forgets its gate still can't
  # create an unauthorized submission. Creation-only (new_record?): grading
  # updates to existing rows never re-run authorization. Applies to binary
  # submissions too (the old version skipped them via `return if source==nil`,
  # and its errors[:base] << never registered on Rails >= 6.1 — the check had
  # been a silent no-op). Trusted server-side tooling that must write
  # submissions regardless (repair shadows, replay engines, model-solution
  # import) bypasses explicitly with save!(validate: false).
  def must_have_valid_problem
    if self.problem.nil?
      errors.add(:problem, :blank)
    elsif self.new_record? && !self.user.can_submit_to_problem?(self.problem)
      errors.add(:base, 'Authorization error: you have no right to submit to this problem')
    end
  end

  # callbacks
  def assign_latest_number_if_new_recond
    return if !self.new_record?
    # Unfiltered on purpose: shadows occupy numbers in the same unique
    # sequence (index on user_id, problem_id, number), so the next number
    # must be computed across ALL rows including shadows.
    latest = Submission.where(user_id: self.user_id, problem_id: self.problem_id).last
    self.number = (latest==nil) ? 1 : latest.number + 1
  end

  public
end
