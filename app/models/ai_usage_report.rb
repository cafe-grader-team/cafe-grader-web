# Read-only analytics over one contest's LLM calls: viva interview turns,
# viva grading, and submission-assist ("Codey") requests. A PORO, not an AR
# model — it only reads. Scoped to the contest's enrolled users and problems
# over the contest window (extended by the largest per-user offset/extra time,
# a coarse bound; per-user precision is not needed for usage reporting).
#
# Time semantics (a call carries up to three, all reported in seconds; the
# page calls them queue time, AI time and wait):
#   queued_s — request queued -> provider call started (started_at - created_at).
#              Available for viva turns and assists (placeholder row created at
#              enqueue). Nil for grades (their row is created after the call) and
#              for rows written before the timing columns existed (rev 2135).
#   model_s  — "AI time": the provider round-trip (llm_latency_ms). Nil on
#              pre-timing rows.
#   total_s  — "wait", what the user actually waited: for turns/assists,
#              updated_at - created_at (queue + AI time + save); for grades,
#              model_s.
class AiUsageReport
  BUCKET = 300 # seconds
  KINDS  = ["viva turn", "assist", "viva grade"].freeze
  # Validated categorical palette (dataviz skill): blue / orange / aqua.
  COLORS = {"viva turn" => "#2a78d6", "assist" => "#eb6834", "viva grade" => "#1baf7a"}.freeze

  Call = Struct.new(
    :kind, :at, :user_id, :login, :problem_id, :problem_name, :submission_id,
    :model, :queued_ms, :model_ms, :total_ms, :tokens_in, :tokens_out, :cost, :points, :status,
    keyword_init: true
  )

  def initialize(contest)
    @contest = contest
  end

  def window
    extra  = @contest.contests_users.maximum(:extra_time_second).to_i
    offset = @contest.contests_users.maximum(:start_offset_second).to_i
    (@contest.start - offset.seconds)..(@contest.stop + extra.seconds)
  end

  def problem_ids = @problem_ids ||= @contest.problems.pluck(:id)
  def user_ids    = @user_ids    ||= @contest.contests_users.where(enabled: true).pluck(:user_id)
  def enrolled    = @contest.contests_users.count

  # --- the raw call list (memoized), built from three sources ---
  def calls
    @calls ||= (turn_calls + assist_calls + grade_calls).sort_by { |c| c.at || Time.at(0) }
  end

  def summary
    turns   = calls.select { |c| c.kind == "viva turn" }
    assists = calls.select { |c| c.kind == "assist" }
    grades  = calls.select { |c| c.kind == "viva grade" }
    priced  = assists.reject { |c| c.cost.nil? }
    sess    = viva_sessions
    {
      sessions_opened:  sess.size,
      students:         sess.map { |s| s[:user_id] }.uniq.size,
      enrolled:         enrolled,
      answered:         sess.count { |s| s[:answers].positive? },
      never_answered:   sess.count { |s| s[:answers].zero? },
      turns:            turns.size,
      turn_cost:        turns.sum { |c| c.cost.to_f },
      turn_wait_p95:    Stats.percentile(turns.map { |c| total_s(c) }, 0.95),
      assists:          assists.size,
      assist_students:  assists.map { |c| c.user_id }.uniq.size,
      assist_points:    assists.sum { |c| c.points.to_f },
      assist_dollars:   priced.sum { |c| c.cost.to_f },
      assist_priced:    priced.size,
      assists_total:    assists.size,
      assist_wait_p95:  Stats.percentile(assists.map { |c| total_s(c) }, 0.95),
      grades:           grades.size,
      grades_after_window: grades.count { |c| c.at && c.at > window.end },
      grade_cost:       grades.sum { |c| c.cost.to_f },
      grade_wait_p95:   Stats.percentile(grades.map { |c| total_s(c) }, 0.95),
      # Tokens sent to (in) and written by (out) the model. Viva turns and
      # assists record them; viva grades do not, so the totals leave grading
      # out. A call without a count adds 0.
      turn_tokens_in:   turns.sum { |c| c.tokens_in.to_i },
      turn_tokens_out:  turns.sum { |c| c.tokens_out.to_i },
      assist_tokens_in:  assists.sum { |c| c.tokens_in.to_i },
      assist_tokens_out: assists.sum { |c| c.tokens_out.to_i },
      # Every dollar the contest's AI calls cost: viva turns + viva grading +
      # the assists that carry a provider price (unpriced ones add nothing).
      total_cost:       turns.sum { |c| c.cost.to_f } + grades.sum { |c| c.cost.to_f } + priced.sum { |c| c.cost.to_f }
    }
  end

  # One row per kind. `calls` is every call of that kind; the wait percentiles
  # are over the ones that carry a wait (`timed`), the AI-time ones over those
  # that carry an AI time. Grade rows and pre-timing rows have no latency, so a
  # row can show calls>0 with timed=0 and a blank AI time.
  def distribution
    KINDS.map do |kind|
      ks    = calls.select { |c| c.kind == kind }
      waits = ks.map { |c| total_s(c) }.compact
      ai    = ks.map { |c| ai_s(c) }.compact
      {
        kind: kind, calls: ks.size, timed: waits.size,
        mean: Stats.mean(waits), p50: Stats.percentile(waits, 0.5),
        p90: Stats.percentile(waits, 0.9), p95: Stats.percentile(waits, 0.95),
        p99: Stats.percentile(waits, 0.99), max: waits.max,
        over_60: waits.empty? ? 0 : (100.0 * waits.count { |w| w > 60 } / waits.size).round,
        ai_mean: Stats.mean(ai), ai_p95: Stats.percentile(ai, 0.95)
      }
    end
  end

  def by_model
    calls.select { |c| c.kind == "assist" }.group_by(&:model).map do |model, cs|
      waits  = cs.map { |c| total_s(c) }.compact
      ai     = cs.map { |c| ai_s(c) }.compact
      priced = cs.reject { |c| c.cost.nil? }
      {
        model: model, requests: cs.size, students: cs.map(&:user_id).uniq.size,
        points: cs.sum { |c| c.points.to_f }, dollars: priced.sum { |c| c.cost.to_f },
        priced: priced.size, mean_wait: Stats.mean(waits), p95: Stats.percentile(waits, 0.95), max: waits.max,
        ai_mean: Stats.mean(ai), ai_p95: Stats.percentile(ai, 0.95)
      }
    end.sort_by { |r| -r[:requests] }
  end

  def by_problem
    calls.group_by(&:problem_id).map do |pid, cs|
      {
        problem: problem_name(pid), turns: cs.count { |c| c.kind == "viva turn" },
        grades: cs.count { |c| c.kind == "viva grade" }, assists: cs.count { |c| c.kind == "assist" },
        students: cs.map(&:user_id).uniq.size, dollars: cs.sum { |c| c.cost.to_f },
        p95: Stats.percentile(cs.map { |c| total_s(c) }, 0.95)
      }
    end.sort_by { |r| r[:problem].to_s }
  end

  # Sessions whose interview opened but the student never answered.
  def never_answered
    viva_sessions.select { |s| s[:answers].zero? }.map do |s|
      {login: s[:login], opened_at: s[:opened_at], greeting_wait: s[:greeting_wait], submission_id: s[:submission_id]}
    end.sort_by { |r| r[:opened_at] || Time.at(0) }
  end

  def counts_chart
    {
      labels: buckets.map { |b| bucket_label(b) },
      datasets: KINDS.map do |kind|
        {label: kind, backgroundColor: COLORS[kind],
         data: buckets.map { |b| bucketed[b][kind].size }}
      end
    }
  end

  def wait_chart
    {
      labels: buckets.map { |b| bucket_label(b) },
      datasets: KINDS.map do |kind|
        {label: kind, borderColor: COLORS[kind], backgroundColor: COLORS[kind], fill: false,
         data: buckets.map { |b| w = bucketed[b][kind]; w.empty? ? nil : (w.sum { |c| total_s(c).to_f } / w.size).round(1) }}
      end
    }
  end

  # DataTable feed. Times as seconds; nil timings render blank.
  def calls_json
    calls.map do |c|
      {
        at: c.at&.iso8601, kind: c.kind, login: c.login, problem: c.problem_name, model: c.model,
        queued_s: ms_to_s(c.queued_ms), model_s: ms_to_s(c.model_ms), total_s: total_s(c),
        tokens_in: c.tokens_in, tokens_out: c.tokens_out,
        cost: c.cost.nil? ? nil : c.cost.to_f.round(4), status: c.status, submission_id: c.submission_id
      }
    end
  end

  private

  def total_s(c)
    return ms_to_s(c.model_ms) if c.kind == "viva grade" # no queued span on a grade row
    c.total_ms.nil? ? nil : (c.total_ms / 1000.0).round(1)
  end

  def ai_s(c) = ms_to_s(c.model_ms)

  def ms_to_s(ms) = ms.nil? ? nil : (ms / 1000.0).round(1)

  # .regular: near-miss shadows and author test-drives are not student usage.
  def sub_ids
    @sub_ids ||= Submission.regular.where(problem_id: problem_ids, user_id: user_ids).pluck(:id)
  end

  def turn_calls
    return [] if sub_ids.empty?
    VivaTurn.where(role: :assistant, submission_id: sub_ids, created_at: window)
            .joins(submission: :user)
            .pluck(:submission_id, "submissions.user_id", "submissions.problem_id", "users.login",
                   :llm_model, :created_at, :updated_at, :llm_started_at, :llm_latency_ms, :token_count_in, :token_count_out, :cost, :status)
            .map do |sid, uid, pid, login, model, cat, uat, sat, lat, tin, tout, cost, status|
      Call.new(kind: "viva turn", at: cat, user_id: uid, login: login, problem_id: pid, problem_name: problem_name(pid),
               submission_id: sid, model: model, queued_ms: queued_ms(cat, sat),
               model_ms: lat, total_ms: ((uat - cat) * 1000).round, tokens_in: tin, tokens_out: tout,
               cost: cost, points: nil, status: status)
    end
  end

  def assist_calls
    return [] if sub_ids.empty?
    Comment.where(kind: :llm_assist, commentable_type: "Submission", commentable_id: sub_ids, created_at: window)
           .joins("JOIN submissions ON submissions.id = comments.commentable_id JOIN users ON users.id = submissions.user_id")
           .pluck("comments.commentable_id", "submissions.user_id", "submissions.problem_id", "users.login",
                  "comments.llm_model", "comments.created_at", "comments.updated_at", "comments.llm_started_at",
                  "comments.llm_latency_ms", "comments.prompt_tokens", "comments.completion_tokens",
                  "comments.llm_cost", "comments.cost", "comments.status")
           .map do |sid, uid, pid, login, model, cat, uat, sat, lat, tin, tout, dollars, points, status|
      Call.new(kind: "assist", at: cat, user_id: uid, login: login, problem_id: pid, problem_name: problem_name(pid),
               submission_id: sid, model: model, queued_ms: queued_ms(cat, sat),
               model_ms: lat, total_ms: ((uat - cat) * 1000).round, tokens_in: tin, tokens_out: tout,
               cost: dollars, points: points, status: status)
    end
  end

  # Every grader run counts — superseded and failed runs cost money too (one
  # viva_grades row per run since the grade-history change, 2026-09-23).
  # A run belongs to the contest when its session STARTED in the window,
  # however late it ran (doc/viva-visibility.md: a viva is bucketed by session
  # start). Most first gradings land after the bell (Finish open vivas), and
  # regrades later; filtering on graded_at counted 23 of Quiz 1's 151 runs.
  def grade_calls
    return [] if sub_ids.empty?
    VivaGrade.where(submission_id: sub_ids)
             .joins(submission: :user)
             .where(submissions: {submitted_at: window})
             .pluck(:submission_id, "submissions.user_id", "submissions.problem_id", "users.login",
                    :llm_model, :graded_at, :llm_latency_ms, :cost, :total_points)
             .map do |sid, uid, pid, login, model, gat, lat, cost, total|
      Call.new(kind: "viva grade", at: gat, user_id: uid, login: login, problem_id: pid, problem_name: problem_name(pid),
               submission_id: sid, model: model, queued_ms: nil, model_ms: lat, total_ms: nil,
               tokens_in: nil, tokens_out: nil, cost: cost, points: nil, status: total.nil? ? "error" : "ok")
    end
  end

  def queued_ms(created_at, started_at)
    return nil if started_at.nil? || created_at.nil?
    ((started_at - created_at) * 1000).round
  end

  def problem_name(pid) = names[pid]
  def names = @names ||= @contest.problems.pluck(:id, :name).to_h

  # One row per viva session (submission) that opened an interview: answers
  # count, when it opened, and how long the first (greeting) turn took.
  def viva_sessions
    @viva_sessions ||= begin
      return [] if sub_ids.empty?
      subs = Submission.where(id: sub_ids)
                       .where(submitted_at: window)
                       .where(id: VivaTurn.select(:submission_id).distinct)
                       .joins(:user).pluck(:id, :user_id, "users.login", :submitted_at)
      ids     = subs.map(&:first)
      answers = VivaTurn.where(submission_id: ids, role: :student).group(:submission_id).count
      greet   = VivaTurn.where(submission_id: ids, role: :assistant, sequence: 1)
                        .pluck(:submission_id, :created_at, :updated_at).to_h { |sid, c, u| [sid, (u - c).round] }
      subs.map do |sid, uid, login, opened|
        {submission_id: sid, user_id: uid, login: login, opened_at: opened,
         answers: answers[sid].to_i, greeting_wait: greet[sid]}
      end
    end
  end

  def buckets
    @buckets ||= begin
      b0 = (window.begin.to_i / BUCKET) * BUCKET
      b1 = (window.end.to_i / BUCKET) * BUCKET
      (b0..b1).step(BUCKET).map { |t| Time.zone.at(t) }
    end
  end

  def bucketed
    @bucketed ||= begin
      h = buckets.to_h { |b| [b, Hash.new { |hh, k| hh[k] = [] }] }
      calls.each do |c|
        next if c.at.nil?
        key = Time.zone.at((c.at.to_i / BUCKET) * BUCKET)
        h[key][c.kind] << c if h.key?(key)
      end
      h
    end
  end

  def bucket_label(b) = b.strftime("%H:%M")
end
