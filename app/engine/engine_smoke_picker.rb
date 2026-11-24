# Chooses the submission that `bin/rails engine:smoke SUB=auto` regrades on
# this host — the post-deploy grading check the deploy pipeline runs before it
# restarts anything (2026-09-17; the gap it closes is how rev 2045 reached nine
# servers, see doc/backlog.md Resolved). Submission ids differ per host, so a
# hard-coded SUB= would be right on one server and wrong on eight; this picks
# from the host's own data instead.
#
# The rules exist to make a non-zero EngineSmoke exit trustworthy, i.e. a real
# engine fault and not the submission's own quirks:
#   - done, regular (not a near-miss shadow), non-viva, full score — so the run
#     crosses compile, every testcase through the checker, and the scorer;
#   - one of LANGUAGE_ORDER, tried in that order — every judge host compiles
#     C++, most C and Python; nothing else is guaranteed anywhere;
#   - in a language its problem still accepts — grading saves the submission
#     and Submission#assign_language relabels it to a single-language
#     problem's only language, so a 2024 C++ submission on a problem now
#     limited to Python ran as Python and crashed every testcase (false
#     "verdict DIFFERS", comprog-grader 2026-09-25);
#   - slowest testcase used at most RUNTIME_MARGIN of the time limit — a timing
#     wobble cannot flip P<->T and give a false "verdict DIFFERS";
#   - graded after the live dataset and its testcases last changed — the stored
#     grade really is against the dataset the run will use;
#   - testcases x time_limit within MAX_BUDGET_SECONDS — the check stays cheap
#     (fleet runs took 2-20 s on 2026-08-30);
#   - most recent first — a recent submission's testcase files are still on
#     disk, which is not true of every old dataset on every host.
class EngineSmokePicker
  LANGUAGE_ORDER     = %w[cpp c python].freeze
  RUNTIME_MARGIN     = 0.5   # share of the time limit the slowest testcase may have used
  MAX_BUDGET_SECONDS = 60    # worst case for the whole run: testcases x time_limit
  SCAN_LIMIT         = 200   # most recent full-score submissions examined per language

  def initialize(language_order: LANGUAGE_ORDER, runtime_margin: RUNTIME_MARGIN,
                 max_budget_seconds: MAX_BUDGET_SECONDS, scan_limit: SCAN_LIMIT)
    @language_order = language_order
    @runtime_margin = runtime_margin
    @max_budget_seconds = max_budget_seconds
    @scan_limit = scan_limit
  end

  # The chosen Submission, or nil when nothing on this host qualifies.
  def pick
    @language_order.each do |lang|
      found = candidates(lang).find { |sub| suitable?(sub) }
      return found if found
    end
    nil
  end

  # One line an operator can read in the deploy log: why this one qualifies.
  def describe(sub)
    ds = sub.problem.live_dataset
    "#{sub.language.name}, problem #{sub.problem_id} #{sub.problem.name}, dataset #{ds.id} " \
      "(#{ds.testcases.size} testcases, #{ds.time_limit}s limit), graded #{sub.graded_at}, " \
      "slowest testcase #{sub.max_runtime.to_i}ms"
  end

  private

  def candidates(lang)
    Submission.regular.done
      .joins(:problem, :language)
      .where(languages: {name: lang})
      .where.not(problems: {compilation_type: Problem.compilation_types[:viva_exam]})
      .where.not(problems: {live_dataset_id: nil})
      .where('submissions.points = problems.full_score')
      .where.not(graded_at: nil).where.not(max_runtime: nil)
      .order(graded_at: :desc, id: :desc)
      .limit(@scan_limit)
      .includes(problem: {live_dataset: :testcases})
  end

  def suitable?(sub)
    # blank permitted_lang = every language; when_blank skips the Language query
    return false unless sub.problem.get_permitted_lang_as_ids(when_blank: [sub.language_id]).include?(sub.language_id)
    ds = sub.problem.live_dataset
    tcs = ds.testcases
    return false if tcs.empty?
    limit_ms = ds.time_limit.to_f * 1000
    return false if sub.max_runtime.to_f > limit_ms * @runtime_margin
    return false if tcs.size * ds.time_limit.to_f > @max_budget_seconds
    last_change = [ds.updated_at, *tcs.map(&:updated_at)].compact.max
    return false if last_change && sub.graded_at <= last_change
    true
  end
end
