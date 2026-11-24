class Submission < ApplicationRecord
  enum :tag, {default: 0, model: 1}, prefix: true
  enum :status, {submitted: 0, evaluating: 1, done: 2, compilation_error: 3, compilation_success: 4, grader_error: 5}

  # Statuses from which no further grading job will ever run: the submission
  # has a grade (or a verdict that it cannot get one) and only an explicit
  # Rejudge moves it again. compilation_success is NOT here — it means
  # "compiled, evaluation still to come". Used by Job.reclaim_orphaned! to
  # tell a live stall apart from a job whose work has already been settled
  # some other way.
  GRADING_FINAL_STATUSES = %w[done compilation_error grader_error].freeze


  belongs_to :language
  belongs_to :problem
  belongs_to :user

  has_many :evaluations, dependent: :destroy

  belongs_to :repaired_from, class_name: 'Submission', optional: true
  has_many :repair_attempts, class_name: 'SubmissionRepair', foreign_key: :original_submission_id

  # viva exam
  has_many :viva_turns, -> { order(:sequence) }, dependent: :destroy
  # One viva_grades row per grader run (design
  # docs/superpowers/specs/2026-09-23-viva-grade-history-design.md).
  # `viva_grade` is the CURRENT grade — the run whose total_points `points`
  # holds (nil while grading is in flight or after a failed first grading);
  # `viva_grades` is the full history. The scope lands in the JOIN condition,
  # so `joins(:viva_grade)` and `where.missing(:viva_grade)` mean "current".
  has_many :viva_grades, dependent: :destroy
  has_one  :viva_grade, -> { where(superseded_at: nil) }
  # Staff member who used "Allow another attempt" on this session.
  belongs_to :viva_retake_granted_by, class_name: 'User', optional: true

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

  # `regular` = a real, student-facing submission: NOT a near-miss shadow and
  # NOT an author's viva test-drive. Every student-visible query, every quota
  # count and every report must read .regular; the judge worker, admin
  # monitoring, number-assignment and the viva reaper must NOT filter.
  #   - Shadows (Near-Miss Grading) are machine-generated repaired copies;
  #     repaired_from_id points at the original. Exclusion audit:
  #     docs/superpowers/plans/2026-07-30-near-miss-grading.md.
  #   - Test-drives are an editor/admin sitting their own viva
  #     (VivaSessionsController#test_drive); graded like a real session but
  #     never counted anywhere. Design:
  #     docs/superpowers/specs/2026-09-23-viva-test-drive-design.md.
  scope :regular,     -> { where(repaired_from_id: nil, test_drive: false) }
  scope :shadow,      -> { where.not(repaired_from_id: nil) }
  scope :test_drives, -> { where(test_drive: true) }

  # Ungraded submissions the judge workers still owe a verdict. Viva sessions
  # are LLM-graded off the judge queue, so graded_at = nil there is normal
  # mid-interview (or abandoned) state, not backlog; they are excluded through
  # the durable 'viva' sentinel language (Language::VIVA_NAME). The navbar
  # "backlogs!" badge (ApplicationController#header_info) and the grader
  # monitor page (GradersController#index) both read this scope so the two
  # can never disagree — they did on cedt-grader 2026-09-12: badge 48, all of
  # them abandoned viva_basic sessions, real judge queue 0.
  scope :judge_backlog, -> {
    where(graded_at: nil)
      .where.not(language_id: Language.where(name: Language::VIVA_NAME).select(:id))
  }

  # Viva submissions parked in :evaluating with no CURRENT grade row
  # (where.missing on the scoped has_one), older than STALE_EVALUATING_AFTER
  # — i.e. what fail_stale_viva_evaluating! would sweep right now. A current
  # row on an :evaluating submission means adoption is mid-write
  # (Submission#adopt_viva_grade! sets the run current, then flips status)
  # — a different bug if it lingers, and NOT something this scope or the
  # sweeper should touch. Superseded rows (earlier runs, failed runs) do not
  # count: a regrade of a graded session never enters :evaluating at all.
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
      # the final score is not computed here: calculate_max_score applies the
      # help-deduction rule (HelpDeduction) in Ruby, with the deduction cap
      .select('submitted_at')
      .select('submissions.id as sub_id')
      .select('submissions.problem_id,submissions.user_id')
      .select('LLM_ASSIST.llm_cost, LLM_ASSIST.llm_count')
      .select('HINT_REVEAL.hint_cost, HINT_REVEAL.hint_count')
  }


  def shadow? = repaired_from_id.present?

  def add_judge_job(dataset = problem.live_dataset, priority = 0)
    Job.supersede!(self)
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

  # Statuses from which one more grader run may be queued: the interview is
  # over. A `submitted` session is still being interviewed.
  VIVA_REGRADABLE_STATUSES = %w[done grader_error evaluating].freeze

  class NotRegradable < StandardError; end

  # True when the current grade run exists and carries points.
  def valid_viva_grade?
    viva_grades.current.where.not(total_points: nil).exists?
  end

  # Make `grade` (one of this submission's runs) the current grade and copy
  # its result onto the submission. The displaced current run is labelled
  # `reason` — 'replaced' when a newer run wins, 'reverted' when an admin
  # (Make current) or viva:regrade_revert re-adopts an older one; a displaced
  # FAILED run is always labelled 'error'. Runs under the row lock so two
  # parallel decisions serialise; the grader service, the Make current button
  # and Viva::Regrader.revert all come through here. Returns the displaced
  # run as read under the lock (nil when there was none, or `grade` was
  # already current) — the Make current audit row records it.
  def adopt_viva_grade!(grade, reason: 'replaced', now: Time.zone.now)
    raise ArgumentError, 'grade belongs to another submission' unless grade.submission_id == id
    raise ArgumentError, 'cannot adopt a failed run' unless grade.valid_grade?
    with_lock do
      old = viva_grade
      old = nil if old&.id == grade.id
      old&.supersede!(reason: old.valid_grade? ? reason : 'error', by: grade, now: now)
      grade.update!(superseded_at: nil, superseded_reason: nil, superseded_by_id: nil)
      update!(points: grade.total_points, status: :done, graded_at: grade.graded_at || now,
              grader_comment: viva_result_marker)
      old
    end
  end

  # Queue one more grader run for this viva session — the admin Re-run button
  # and Viva::Regrader batches. An existing valid grade is never touched: the
  # new run is written by Llm::VivaGradeAssist#handle_response and adopted,
  # kept as 'lower' or recorded as 'error' there. Only when no valid grade
  # exists (first grading failed or never finished) does the session go back
  # to :evaluating, so the student sees "Grading in progress" and the stuck
  # sweeper applies, exactly as for a first grading. The job is enqueued after
  # the lock has committed, with only the options actually given.
  def regrade_viva!(model: nil, never_lower: true, requested_by: nil, batch_id: nil)
    raise NotRegradable, 'not a viva submission' unless problem.viva_exam?
    with_lock do
      # Checked after the lock's reload, so a session that is no longer
      # regradable is refused (the raise rolls the lock's transaction back).
      raise NotRegradable, 'the interview is still open, end it first' unless VIVA_REGRADABLE_STATUSES.include?(status.to_s)
      unless valid_viva_grade?
        # A failed run left current (legacy rows) is filed as error first,
        # so the session has no current row while it is graded again.
        current = viva_grade
        current.supersede!(reason: 'error') if current&.failed?
        update!(status: :evaluating, points: nil, graded_at: nil, grader_comment: nil)
      end
    end
    kwargs = {model: model.presence, never_lower: never_lower, requested_by_id: requested_by&.id, batch_id: batch_id}.compact
    # Batch runs (Viva::Regrader) queue behind live interview turns and first
    # gradings on the shared `viva` queue: Solid Queue runs the lower priority
    # number first, and the default is 0.
    job = batch_id.present? ? Llm::VivaGradeAssistJob.set(priority: 10) : Llm::VivaGradeAssistJob
    job.perform_later(self, **kwargs)
  end


  def set_grading_complete(point, grading_text, max_time, max_mem)
    update(points: point, status: :done, graded_at: Time.zone.now, grader_comment: grading_text, max_runtime: max_time, peak_memory: max_mem)
  end

  def set_grading_error(error_text)
    update(points: 0, status: :grader_error, graded_at: Time.zone.now, grader_comment: error_text)
  end

  # Marks any viva submission stuck in :evaluating (grading in flight, no
  # current viva_grade row) for longer than `threshold` as :grader_error, so the
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
  # (no turn activity, status still :submitted, not archived) is handed to
  # finalize_open_viva! — graded if the student answered at least once,
  # archived if greeting-only. Sessions with a :processing turn are skipped
  # here (and re-checked under the lock): VivaTurn.fail_stale! owns stuck
  # turns, and once it flips them to :error a later sweep picks the session
  # up. Registered production-only in config/recurring.yml — in development
  # it would silently spend LLM tokens grading forgotten local sessions.
  def self.reap_abandoned_vivas!(idle_for: ABANDONED_VIVA_REAP_AFTER, now: Time.zone.now)
    cutoff = now - idle_for
    stale = submitted
              .joins(:problem).merge(Problem.viva_exam)
              .where(viva_archived_at: nil)
              .where("submissions.submitted_at < ?", cutoff)
              .where.not(id: VivaTurn.where("updated_at >= ?", cutoff).select(:submission_id))
              .where.not(id: VivaTurn.where(status: :processing).select(:submission_id))
    counts = {graded: 0, archived: 0}
    stale.find_each do |sub|
      outcome = sub.finalize_open_viva!(
        graded_note:   '(session expired after inactivity — grading begins)',
        archived_note: '(session expired after inactivity — archived)',
        now: now)
      counts[outcome] += 1 if counts.key?(outcome)
    end
    Rails.logger.info "Submission.reap_abandoned_vivas!: graded #{counts[:graded]}, archived #{counts[:archived]} abandoned viva session(s)" if counts.values.sum.positive?
    counts
  end

  # Finalizes ONE open viva session — the single step behind both the 24 h
  # reaper above and the contest page's "Finish open vivas" button
  # (Contest#finish_open_vivas!), so the two can never drift apart:
  #   - with at least one student answer: closing system turn, :evaluating,
  #     grade job with no model: (the grade service default decides, rev
  #     2011) — exactly the hard-cap / End-button path;
  #   - greeting-only: closing system turn + archived (the restart flow's
  #     soft-hide). Under the engaged-only limit accounting (rev 2014) it
  #     never counted anyway.
  # Runs under the same row lock as VivaSessionsController#answer / #finish
  # and re-checks the session inside it, so a student's answer landing at the
  # same instant is serialised, not doubled. Returns :graded, :archived or
  # :skipped — skipped when the session is no longer open (ended, archived,
  # already grading) or an assistant reply is still :processing. The grade
  # job is enqueued after the lock block has committed.
  def finalize_open_viva!(graded_note:, archived_note:, now: Time.zone.now)
    outcome = with_lock do
      next :skipped unless submitted? && viva_archived_at.nil?
      next :skipped if viva_turns.where(status: :processing).exists?
      if viva_turns.where(role: :student).exists?
        viva_turns.create!(role: :system, status: :ok, content: graded_note)
        update!(status: :evaluating)
        :graded
      else
        viva_turns.create!(role: :system, status: :ok, content: archived_note)
        update!(viva_archived_at: now)
        :archived
      end
    end
    Llm::VivaGradeAssistJob.perform_later(self) if outcome == :graded
    outcome
  end

  # "Allow another attempt" (design 2026-10-07, A4; staff only — the caller
  # authorizes). Archives the session whatever its status — an open interview
  # after an infrastructure failure, a session still being graded (its grade
  # lands and still counts toward the best score), or one already archived —
  # and stamps the grant, so Viva::StartPolicy stops counting it and the
  # student can start exactly one more. An open session archived this way is
  # never graded. Idempotent under the row lock: a second click (or a second
  # staff member) gets :already and changes nothing. Returns :granted,
  # :already, :test_drive (test-drives are outside the limit) or :not_viva.
  def grant_viva_retake!(by:, now: Time.zone.now)
    return :not_viva unless problem&.viva_exam?
    return :test_drive if test_drive?

    with_lock do
      next :already if viva_retake_granted_at.present?

      update!(viva_archived_at: viva_archived_at || now,
              viva_retake_granted_at: now,
              viva_retake_granted_by_id: by&.id)
      :granted
    end
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

  # Full score on the 0–100 points scale: a submission at it cannot ask for
  # AI help. The spending limit used to be this constant; it is now
  # HelpDeduction.spending_limit_for (a contest's, else the site setting
  # system.llm_assist_spending_limit, 100 by default).
  LLM_ASSIST_FULL_SCORE = 100

  # Why the assist picker should not offer `model` for this submission, or nil
  # when it may. Shared by the picker (submissions/_add_assist) and
  # CommentsController#can_request_llm, so the UI never shows a button the
  # controller would refuse. Prod copy before this existed: 190 submissions had
  # the same model asked twice, 126 requests were made on full-score
  # submissions, 10 (user, problem) pairs had spent more than the full score.
  def llm_assist_refusal(model)
    assists = comments.where(kind: 'llm_assist')
    return 'a request is still running' if assists.where(status: 'processing').exists?
    return "#{model} already answered" if assists.where(status: 'ok', llm_model: model).exists?
    return 'already full score' if points.to_f >= LLM_ASSIST_FULL_SCORE

    # the spending limit (HelpDeduction, spec 2026-11-21): the owner's running
    # contests' limit, else the site setting; all AI help on the problem, ever
    running = HelpDeduction.running_contests_by_problem(user, [problem_id])[problem_id] || []
    limit = HelpDeduction.spending_limit_for(running)
    return 'no AI help is allowed on this problem' if limit.zero?

    spent = HelpDeduction.ai_spent(user, problem_id)
    if spent >= limit
      return "already spent #{spent.to_i} of the #{limit} points of AI help allowed on this problem"
    end
    nil
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
  #
  # deduction_cap: the most hints + AI help count against a problem's full
  # score (HelpDeduction, spec 2026-11-21); nil = no cap. total_cost_<id> is
  # the counted deduction, raw_cost_<id> the uncapped hint + AI points.
  def self.calculate_max_score(records, users, problems, with_comments: true, deduction_cap: nil)
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
          result[:score][sub.login]["final_score_#{sub.problem_id}"] =
            HelpDeduction.final_score(sub.max_score, sub.hint_cost, sub.llm_cost, deduction_cap).to_d

          result[:score][sub.login]["total_cost_#{sub.problem_id}"] = nil
          result[:score][sub.login]["raw_cost_#{sub.problem_id}"] = nil
          unless sub.llm_cost.nil? && sub.hint_cost.nil?
            result[:score][sub.login]["total_cost_#{sub.problem_id}"] =
              HelpDeduction.deduction(sub.hint_cost, sub.llm_cost, deduction_cap).to_d
            result[:score][sub.login]["raw_cost_#{sub.problem_id}"] = (sub.hint_cost.to_f + sub.llm_cost.to_f).to_d
          end
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
