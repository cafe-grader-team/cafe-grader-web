module Viva
  # The one start rule for real (non-test-drive) viva sessions — design
  # 2026-10-07 (docs/superpowers/specs/2026-10-07-viva-retakes-and-viva-check-design.md,
  # A1–A3). VivaSessionsController#start refuses with #refusal, #restart and
  # the session page ask #restart_allowed?, and the Viva Info card reads
  # #limit / #starts_left — so they can never disagree.
  #
  # Start limit (problems.viva_daily_limit):
  #   blank -> the site default (viva.practice_daily_start_limit, fallback 3)
  #   N > 0 -> N counted sessions per day
  #   0     -> contest-only: cannot start outside contest mode; one counted
  #            session per day inside it (before 2026-10-07: unlimited)
  # Admins are exempt (#limit is nil). A session counts once the student has
  # answered (greeting-only peeks are free) and stops counting once staff use
  # "Allow another attempt" (submissions.viva_retake_granted_at).
  class StartPolicy
    PRACTICE_DAILY_START_LIMIT_CONF_KEY = 'viva.practice_daily_start_limit'.freeze
    # Used only when that site setting is missing, blank or non-positive: a
    # misconfigured default must fail safe to a limit, never to unlimited.
    DAILY_START_LIMIT_FALLBACK = 3

    attr_reader :problem, :user

    # The problem's own daily figure before the contest-only and admin rules:
    # its viva_daily_limit, or the site default when that is blank.
    def self.daily_limit_for(problem)
      return problem.viva_daily_limit unless problem.viva_daily_limit.nil?

      limit = GraderConfiguration[PRACTICE_DAILY_START_LIMIT_CONF_KEY].to_i
      limit.positive? ? limit : DAILY_START_LIMIT_FALLBACK
    end

    def initialize(problem, user, now: Time.zone.now)
      @problem = problem
      @user    = user
      @now     = now
    end

    def contest_only?
      problem.viva_daily_limit == 0
    end

    # Counted sessions allowed today; nil = unlimited (admin). A contest-only
    # viva allows 1 in contest mode and 0 outside it.
    def limit
      return nil if user.admin?
      return (GraderConfiguration.contest_mode? ? 1 : 0) if contest_only?

      self.class.daily_limit_for(problem)
    end

    # Today's sessions the limit counts: regular (no test-drive), at least one
    # student answer, no staff grant. Archived sessions still count —
    # restarting never refunds the day's budget.
    def counted_today
      @counted_today ||= problem.submissions.regular
                                .where(user: user, viva_retake_granted_at: nil)
                                .where('submitted_at >= ?', @now.beginning_of_day)
                                .joins(:viva_turns).where(viva_turns: {role: :student})
                                .distinct.count
    end

    # nil = unlimited (admin).
    def starts_left
      limit && [limit - counted_today, 0].max
    end

    # nil when the user may start a session now, else the student-facing reason.
    def refusal
      return nil if user.admin?
      if contest_only? && !GraderConfiguration.contest_mode?
        return 'This viva can only be taken during a contest.'
      end
      return nil if counted_today < limit

      if GraderConfiguration.contest_mode?
        used = limit == 1 ? 'your attempt' : "all #{limit} of today's attempts"
        "You have used #{used} for '#{problem.name}'. If something went wrong, ask a proctor: " \
          'staff can allow another attempt (contest page → Reports → Viva check).'
      else
        "Daily practice limit reached for '#{problem.name}' (#{limit}/day). Try again tomorrow."
      end
    end

    # May the owner archive `submission` with Restart (A3)? Only when they can
    # start again afterwards: a test-drive, a session with no answer (it never
    # counted), or a start left today with this session already counted.
    def restart_allowed?(submission)
      submission.test_drive? ||
        !submission.viva_turns.where(role: :student).exists? ||
        refusal.nil?
    end
  end
end
