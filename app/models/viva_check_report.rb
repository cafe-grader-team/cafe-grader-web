# Read-only "Viva check" over one contest (design 2026-10-07,
# docs/superpowers/specs/2026-10-07-viva-retakes-and-viva-check-design.md §4):
# for every student with a session on one of the contest's viva problems,
# the flags staff should act on during the exam ("needs action") or look at
# afterwards ("worth a look"). Sessions are Contest#submissions on the viva
# problems by the contest's students (Contest#students; staff sessions are
# left out) — regular only (no test-drives, no near-miss shadows), each
# student's own window — archived ones included. A PORO like AiUsageReport.
class VivaCheckReport
  WAITING_REPLY_AFTER = 60.seconds
  NO_ANSWER_AFTER     = 5.minutes
  GRADING_STUCK_AFTER = 5.minutes
  SHORT_ANSWERS       = 3
  HIGH_POINTS         = 50
  ENDED_EARLY_PREFIX  = '(student ended the interview'.freeze

  # Display order. :action flags count toward the contest-page badge; :look do not.
  FLAGS = {
    retook:          {label: 'Retook', level: :action,
                      tip: 'Two or more answered sessions without a staff grant'},
    waiting_reply:   {label: 'Waiting for reply', level: :action,
                      tip: 'An examiner reply has been in progress for 60 seconds or more'},
    reply_failed:    {label: 'Reply failed', level: :action,
                      tip: 'The latest examiner reply of an open session failed; the student sees a Retry button'},
    grading_failed:  {label: 'Grading failed', level: :action,
                      tip: 'Grading failed, or has run 5 minutes without a grade'},
    left_unfinished: {label: 'Left unfinished', level: :action,
                      tip: 'Archived mid-interview with answers and no staff grant: it will never be graded'},
    grade_mismatch:  {label: "Grade doesn't add up", level: :action,
                      tip: 'A rubric item above its maximum, items not summing to the total, or names not in the rubric'},
    no_answer_yet:   {label: 'No answer yet', level: :look,
                      tip: 'Open 5 minutes or more without an answer'},
    short_high:      {label: 'Short but high', level: :look,
                      tip: '3 or fewer answers and 50 or more points'},
    ended_early:     {label: 'Ended early', level: :look,
                      tip: 'The student pressed End interview'},
    rule_flag:       {label: 'Rule-break flag', level: :look,
                      tip: 'The examiner flagged a turn as going outside the exam rules'}
  }.freeze

  Session = Struct.new(:id, :status, :points, :submitted_at, :archived_at, :granted_at, :answers,
                       keyword_init: true)

  Row = Struct.new(:problem, :user_id, :login, :full_name, :sessions, :flags, :details, :grantable_id,
                   keyword_init: true) do
    def latest        = sessions.max_by(&:id)
    def best          = sessions.filter_map(&:points).max
    def answered      = sessions.count { |s| s.answers.positive? }
    def needs_action? = flags.any? { |f| FLAGS.dig(f, :level) == :action }
  end

  Check = Struct.new(:problem, :rubric, :rows, keyword_init: true) do
    def rubric_ok?         = rubric.readable? && rubric.sums_to_100?
    def needs_action_count = rows.count(&:needs_action?) + (rubric_ok? ? 0 : 1)
  end

  def initialize(contest, now: Time.zone.now)
    @contest = contest
    @now     = now
  end

  def viva_problems
    @viva_problems ||= @contest.problems.viva_exam.to_a
  end

  # One Check per viva problem of the contest.
  def checks
    @checks ||= viva_problems.map do |problem|
      rubric = Viva::Rubric.parse(problem.viva_prompt)
      Check.new(problem: problem, rubric: rubric, rows: rows_for(problem, rubric))
    end
  end

  # Students with a needs-action flag, plus one per viva problem whose rubric
  # cannot be checked — the "N to check" badge on the contest page.
  def needs_action_count
    checks.sum(&:needs_action_count)
  end

  def summary
    greet = greeting_waits
    {
      sessions:     subs.size,
      students:     subs.map(&:user_id).uniq.size,
      enrolled:     @contest.students.count,
      answered:     subs.count { |s| answers[s.id].to_i.positive? },
      open_now:     subs.count { |s| s.status == 'submitted' && s.viva_archived_at.nil? },
      graded:       subs.count { |s| s.status == 'done' },
      grading:      subs.count { |s| s.status == 'evaluating' },
      failed:       subs.count { |s| s.status == 'grader_error' },
      greeting_p95: Stats.percentile(greet, 0.95),
      greeting_max: greet.max,
      needs_action: needs_action_count
    }
  end

  private

  def subs
    @subs ||=
      if viva_problems.empty?
        []
      else
        # Students only: a contest editor's (or an enrolled admin's)
        # own sessions are never rows and never count in the tiles.
        @contest.submissions.where(problem_id: viva_problems.map(&:id))
                .where(user_id: @contest.students.select(:id))
                .reorder('submissions.id')
                .select('submissions.id, submissions.user_id, submissions.problem_id, submissions.status',
                        'submissions.points, submissions.submitted_at, submissions.updated_at',
                        'submissions.viva_archived_at, submissions.viva_retake_granted_at')
                .to_a
      end
  end

  def ids
    @ids ||= subs.map(&:id)
  end

  def answers
    @answers ||= ids.empty? ? {} : VivaTurn.where(submission_id: ids, role: :student).group(:submission_id).count
  end

  def ids_with(scope)
    ids.empty? ? Set.new : scope.where(submission_id: ids).distinct.pluck(:submission_id).to_set
  end

  def alerted
    @alerted ||= ids_with(VivaTurn.where(alerted: true))
  end

  def ended_early
    @ended_early ||= ids_with(VivaTurn.where(role: :system).where('content LIKE ?', "#{ENDED_EARLY_PREFIX}%"))
  end

  def waiting
    @waiting ||= ids_with(VivaTurn.where(role: :assistant, status: :processing)
                                  .where('created_at <= ?', @now - WAITING_REPLY_AFTER))
  end

  # submission_id => status ("ok" / "processing" / "error") of its latest assistant turn
  def last_reply_status
    @last_reply_status ||= begin
      rows = ids.empty? ? [] : VivaTurn.where(submission_id: ids, role: :assistant).pluck(:submission_id, :sequence, :status)
      rows.group_by(&:first).transform_values { |rs| rs.max_by { |r| r[1] }[2].to_s }
    end
  end

  # submission_id => [score_json, total_points] of its current grade
  def current_grades
    @current_grades ||=
      if ids.empty?
        {}
      else
        VivaGrade.where(submission_id: ids, superseded_at: nil)
                 .pluck(:submission_id, :score_json, :total_points)
                 .to_h { |sid, json, total| [sid, [json, total]] }
      end
  end

  # Seconds from opening a session to the examiner's first question.
  def greeting_waits
    return [] if ids.empty?

    VivaTurn.where(submission_id: ids, role: :assistant, sequence: 1, status: :ok)
            .pluck(:created_at, :updated_at).map { |c, u| (u - c).round }
  end

  def users_by_id
    @users_by_id ||= User.where(id: subs.map(&:user_id).uniq)
                         .pluck(:id, :login, :full_name).to_h { |id, login, name| [id, [login, name]] }
  end

  def rows_for(problem, rubric)
    subs.select { |s| s.problem_id == problem.id }.group_by(&:user_id).map do |user_id, user_subs|
      flags   = []
      details = {}
      sessions = user_subs.map do |s|
        n = answers[s.id].to_i
        session_flags(s, n, rubric).each do |flag, detail|
          flags << flag
          details[flag] ||= detail if detail
        end
        Session.new(id: s.id, status: s.status.to_s, points: s.points&.to_f, submitted_at: s.submitted_at,
                    archived_at: s.viva_archived_at, granted_at: s.viva_retake_granted_at, answers: n)
      end
      counted = sessions.select { |x| x.answers.positive? && x.granted_at.nil? }
      flags << :retook if counted.size >= 2
      grantable = counted.select { |x| x.submitted_at >= @now.beginning_of_day }.max_by(&:id)
      login, full_name = users_by_id[user_id]
      Row.new(problem: problem, user_id: user_id, login: login, full_name: full_name, sessions: sessions,
              flags: flags.uniq.sort_by { |f| FLAGS.keys.index(f) }, details: details,
              grantable_id: grantable&.id)
    end.sort_by { |r| [r.needs_action? ? 0 : 1, r.flags.empty? ? 1 : 0, r.login.to_s] }
  end

  # [[flag, detail or nil], ...] for one session.
  def session_flags(s, answers_count, rubric)
    out     = []
    status  = s.status.to_s
    open    = status == 'submitted' && s.viva_archived_at.nil?
    granted = s.viva_retake_granted_at.present?
    grade   = current_grades[s.id]

    unless granted
      out << [:waiting_reply, nil]   if s.viva_archived_at.nil? && waiting.include?(s.id)
      out << [:reply_failed, nil]    if open && last_reply_status[s.id] == 'error'
      if status == 'grader_error' || (status == 'evaluating' && grade.nil? && s.updated_at <= @now - GRADING_STUCK_AFTER)
        out << [:grading_failed, nil]
      end
      out << [:left_unfinished, nil] if s.viva_archived_at && status == 'submitted' && answers_count.positive?
    end
    if grade && rubric.readable?
      problems = Viva::Rubric.grade_problems(rubric.weights, grade[0], grade[1])
      out << [:grade_mismatch, "##{s.id}: #{problems.join('; ')}"] if problems.any?
    end
    out << [:no_answer_yet, nil] if open && answers_count.zero? && s.submitted_at <= @now - NO_ANSWER_AFTER
    if status == 'done' && answers_count <= SHORT_ANSWERS && s.points.to_f >= HIGH_POINTS
      out << [:short_high, "##{s.id}: #{answers_count} answers, #{s.points.to_f.round(1)} points"]
    end
    out << [:ended_early, nil] if ended_early.include?(s.id)
    out << [:rule_flag, nil]   if alerted.include?(s.id)
    out
  end
end
