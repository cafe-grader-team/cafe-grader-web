require 'test_helper'

# EngineSmokePicker chooses what `engine:smoke SUB=auto` regrades on a host.
# Each rule below exists so that a non-zero smoke exit means the engine, not
# the submission: full score with a runtime margin (no P<->T flips), graded
# after its dataset last changed (stored grade is against the dataset the run
# uses), non-viva and regular (a real grading chain to cross), a bounded run
# time, and a fixed language order every judge host can compile.
class EngineSmokePickerTest < ActiveSupport::TestCase
  FRESH = 1.hour.from_now      # after the fixtures' (load-time) dataset timestamps
  STALE = 1.year.ago           # before them

  setup do
    @picker = EngineSmokePicker.new
  end

  # ds_add: 2 testcases, 1.0 s limit, prob_add full_score 100.
  def done_sub(problem: problems(:prob_add), language: languages(:Language_cpp), user: users(:john),
               points: nil, graded_at: FRESH, max_runtime: 120, repaired_from: nil)
    sub = Submission.new(user: user, problem: problem, language: language, source: 'int main(){}',
                         submitted_at: graded_at - 1.minute, repaired_from: repaired_from)
    sub.save!(validate: false)
    sub.update_columns(status: Submission.statuses[:done], points: points || problem.full_score,
                       graded_at: graded_at, max_runtime: max_runtime, grader_comment: 'PP')
    sub
  end

  test 'picks the most recently graded suitable submission' do
    older = done_sub(graded_at: FRESH - 30.minutes)
    newer = done_sub(user: users(:james), graded_at: FRESH)
    assert_equal newer, @picker.pick
    assert_not_equal older, @picker.pick
  end

  test 'prefers C++ over C over Python regardless of recency' do
    py  = done_sub(language: languages(:Language_python), graded_at: FRESH + 2.minutes)
    c   = done_sub(user: users(:james), language: languages(:Language_c), graded_at: FRESH + 1.minute)
    cpp = done_sub(user: users(:admin), graded_at: FRESH)
    assert_equal cpp, @picker.pick
    cpp.destroy
    assert_equal c, @picker.pick
    c.destroy
    assert_equal py, @picker.pick
  end

  test 'ignores languages outside the order' do
    done_sub(language: languages(:Language_java))
    assert_nil @picker.pick
  end

  test 'skips viva problems, near-miss shadows and non-full-score submissions' do
    done_sub(problem: problems(:prob_viva))
    original = done_sub(user: users(:james), points: 50)
    done_sub(user: users(:admin), repaired_from: original)
    assert_nil @picker.pick
  end

  test 'skips a submission graded before its live dataset last changed' do
    done_sub(graded_at: STALE)
    assert_nil @picker.pick
    fresh = done_sub(user: users(:james), graded_at: FRESH)
    assert_equal fresh, @picker.pick
  end

  test 'skips a submission whose slowest testcase is over the runtime margin' do
    done_sub(max_runtime: 600)                     # 1.0 s limit -> 500 ms margin
    assert_nil @picker.pick
    ok = done_sub(user: users(:james), max_runtime: 500)
    assert_equal ok, @picker.pick
  end

  test 'skips a dataset whose worst-case run exceeds the budget' do
    done_sub
    assert_nil EngineSmokePicker.new(max_budget_seconds: 1.5).pick   # 2 testcases x 1.0 s
    assert_not_nil EngineSmokePicker.new(max_budget_seconds: 2).pick
  end

  test 'skips a live dataset with no testcases and a problem with no live dataset' do
    done_sub(problem: problems(:hard))              # ds_sub has no testcase fixtures
    problems(:easy).update_columns(live_dataset_id: nil)
    done_sub(problem: problems(:easy), user: users(:james))
    assert_nil @picker.pick
  end

  # Grading saves the submission, and Submission#assign_language relabels it to
  # a single-language problem's only language — so an old C++ submission on a
  # problem that now accepts only Python runs as Python and every testcase
  # crashes (comprog-grader, 2026-09-25: a false "verdict DIFFERS").
  test 'skips a submission whose language its problem no longer accepts' do
    problems(:prob_add).update_columns(permitted_lang: 'python')
    done_sub
    assert_nil @picker.pick
    problems(:prob_add).update_columns(permitted_lang: 'cpp python')
    assert_not_nil @picker.pick
  end

  test 'returns nil on an empty host' do
    assert_nil @picker.pick
  end

  test 'describe names the language, problem, dataset size, limit and runtime' do
    sub = done_sub
    line = @picker.describe(sub)
    assert_includes line, 'cpp'
    assert_includes line, "problem #{sub.problem_id} add"
    assert_includes line, '2 testcases'
    assert_includes line, '120ms'
  end
end
