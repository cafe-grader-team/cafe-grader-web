require "test_helper"

class Replay::CmsReplayTest < ActiveSupport::TestCase
  C = Replay::CmsReplay

  # --- verdict_char -------------------------------------------------------

  test "outcome >= 1.0 is P regardless of text" do
    assert_equal "P", C.verdict_char(1.0, "anything")
    assert_equal "P", C.verdict_char(1, "")
    assert_equal "P", C.verdict_char(1.5, "Output is correct") # a checker could in theory emit >1.0
  end

  test "text matching timed out is T" do
    assert_equal "T", C.verdict_char(0.0, "Execution timed out")
    assert_equal "T", C.verdict_char(0.0, "Execution timed out (wall clock limit exceeded)")
  end

  test "text matching killed or memory is x (segfault/signal or MLE, cafe's combined bucket)" do
    assert_equal "x", C.verdict_char(0.0, "Execution killed (could be triggered by violating memory limits)")
    assert_equal "x", C.verdict_char(0.0, "Execution killed with signal 11")
  end

  test "a fractional outcome with no matching text is partial credit s" do
    assert_equal "s", C.verdict_char(0.5, "Output is partially correct")
  end

  test "zero outcome with no matching text is wrong answer -" do
    assert_equal "-", C.verdict_char(0.0, "Output isn't correct")
    assert_equal "-", C.verdict_char(0.0, "")
  end

  test "list-shaped text (CMS's format-template + args ARRAY column) is handled" do
    # extract_submissions.py already normalises Evaluation.text (a Postgres
    # ARRAY) to a joined String before it reaches Ruby -- but verdict_char
    # itself must not assume a bare String, since a caller could still hand
    # it the raw CMS list shape (a hand-built test fixture, or a future
    # extractor revision).
    assert_equal "T", C.verdict_char(0.0, ["Execution timed out"])
    assert_equal "x", C.verdict_char(0.0, ["Execution killed (could be triggered by violating memory %s)", "limits"])
  end

  # --- cms_verdict_string --------------------------------------------------

  def build_dataset(group_sizes)
    problem = Problem.create!(name: "cmsreplay_#{SecureRandom.hex(3)}", full_name: "CMS replay fixture")
    dataset = Dataset.create!(problem: problem, name: "D1")
    num = 0
    group_sizes.each_with_index do |count, gi|
      count.times do |i|
        num += 1
        Testcase.create!(dataset: dataset, problem: problem, num: num, group: gi + 1,
                         code_name: format("%02d-%02d", gi + 1, i + 1), weight: 1)
      end
    end
    dataset
  end

  test "cms_verdict_string builds in num order and maps each testcase via code_name" do
    dataset = build_dataset([2, 1]) # codenames 01-01, 01-02, 02-01 in num order
    evaluations = {
      "01-01" => { "outcome" => 1.0, "text" => "Output is correct" },
      "01-02" => { "outcome" => 0.0, "text" => "Execution timed out" },
      "02-01" => { "outcome" => 0.4, "text" => "Output is partially correct" }
    }
    assert_equal "PTs", C.cms_verdict_string(evaluations, dataset)
  end

  test "cms_verdict_string follows num order even when it disagrees with code_name's lexicographic order" do
    # code_name "9-1" sorts AFTER "10-1" lexicographically, but num order
    # must win -- the whole point of walking testcases.order(:num) instead
    # of trusting codename string-sort.
    problem = Problem.create!(name: "cmsreplay_#{SecureRandom.hex(3)}", full_name: "Order fixture")
    dataset = Dataset.create!(problem: problem, name: "D1")
    Testcase.create!(dataset: dataset, problem: problem, num: 1, group: 1, code_name: "9-1", weight: 1)
    Testcase.create!(dataset: dataset, problem: problem, num: 2, group: 2, code_name: "10-1", weight: 1)
    evaluations = {
      "9-1"  => { "outcome" => 1.0, "text" => "" },
      "10-1" => { "outcome" => 0.0, "text" => "" }
    }
    assert_equal "P-", C.cms_verdict_string(evaluations, dataset)
  end

  test "cms_verdict_string raises a clear, testcase-identifying error on a missing codename rather than padding" do
    dataset = build_dataset([2])
    evaluations = { "01-01" => { "outcome" => 1.0, "text" => "" } } # "01-02" is missing
    err = assert_raises(RuntimeError) { C.cms_verdict_string(evaluations, dataset) }
    assert_match(/01-02/, err.message)
    assert_match(/#2/, err.message)
  end

  test "cms_verdict_string tolerates symbol-keyed evaluations and per-evaluation hashes" do
    dataset = build_dataset([1])
    evaluations = { "01-01" => { outcome: 1.0, text: "Output is correct" } }
    assert_equal "P", C.cms_verdict_string(evaluations, dataset)
  end

  # --- directory-style codename sanitisation (rev eb25440b2285 follow-up) --

  test "cms_verdict_string matches sanitized cafe code_names against original slashed CMS codenames" do
    # 8 real CMS tasks use directory-style codenames (e.g. "test/1a") that
    # Converters::CmsDumpConverter#safe_codename turns into a safe filename
    # at import time (e.g. "test_1a") -- so Testcase#code_name is the
    # SANITIZED form while the CMS evaluations hash (straight from
    # extract_submissions.py) stays keyed by the ORIGINAL form.
    problem = Problem.create!(name: "cmsreplay_#{SecureRandom.hex(3)}", full_name: "Sanitized codename fixture")
    dataset = Dataset.create!(problem: problem, name: "D1")
    Testcase.create!(dataset: dataset, problem: problem, num: 1, group: 1, code_name: "result_1-01", weight: 1)
    Testcase.create!(dataset: dataset, problem: problem, num: 2, group: 1, code_name: "result_2-01", weight: 1)
    evaluations = {
      "result/1-01" => { "outcome" => 1.0, "text" => "Output is correct" },
      "result/2-01" => { "outcome" => 0.0, "text" => "Output isn't correct" }
    }
    assert_equal "P-", C.cms_verdict_string(evaluations, dataset)
  end

  test "cms_verdict_string raises loudly when two original codenames collide on the same safe name" do
    # Converters::CmsDumpConverter#safe_codename_map already hard-rejects
    # this at import time, so it should be unreachable in practice -- but a
    # hand-built or corrupted sample must fail loudly here too, never
    # silently pick one evaluation over the other.
    dataset = build_dataset([1])
    Testcase.update_all(code_name: "a_b") # what both "a/b" and "a?b" sanitize to (safe_codename replaces any non \w.\- char with "_")
    assert_equal "a_b", Converters::CmsDumpConverter.safe_codename("a/b")
    assert_equal "a_b", Converters::CmsDumpConverter.safe_codename("a?b")
    evaluations = {
      "a/b" => { "outcome" => 1.0, "text" => "" },
      "a?b" => { "outcome" => 0.0, "text" => "" }
    }
    err = assert_raises(RuntimeError) { C.cms_verdict_string(evaluations, dataset) }
    assert_match(/a\/b/, err.message)
    assert_match(/a\?b/, err.message)
    assert_match(/ambiguous/, err.message)
  end

  # --- run: compile-error submissions & score-based verdicts ---------------
  #
  # These exercise C.run end to end but stub Replay::ReplayGrader.grade_sync
  # (same technique as Replay::SubmissionReplayTest) so no real judge/isolate
  # box is needed -- only the report-shaping logic in cms_replay.rb is under
  # test here.

  def build_live_dataset(group_sizes)
    dataset = build_dataset(group_sizes)
    dataset.problem.update!(live_dataset: dataset)
    dataset
  end

  def cpp_entry(id, cms_score:, evaluations: {}, compilation_outcome: nil)
    { "cms_submission_id" => id, "language" => "C++11 / g++", "cms_score" => cms_score,
      "compilation_outcome" => compilation_outcome, "source" => "int main(){}", "evaluations" => evaluations }
  end

  test "a submission with empty CMS evaluations and compilation_outcome fail is classified compile_only, " \
       "never errored, and passes when cafe also scores 0" do
    dataset = build_live_dataset([2])
    problem = dataset.problem
    sample = { "task" => problem.name, "dataset_id" => dataset.id,
               "submissions" => [cpp_entry(1, cms_score: 0.0, compilation_outcome: "fail")] }

    Replay::ReplayGrader.stub :grade_sync, ->(*) { { points: 0.0, grader_comment: nil, status: "compilation_error" } } do
      report = C.run(problem, sample)
      assert_equal 1, report[:replayed]
      assert_equal 1, report[:compile_only]
      assert_equal 0, report[:errored], "compile-error submissions must never be bucketed as errored"
      assert_equal 0, report[:score_mismatch]
      assert_equal 1, report[:score_exact]
      assert_empty report[:mismatch_details]
    end
    assert_equal 0, Submission.joins(:user).where(users: { login: "replay_bot" }).count,
                 "the replayed submission must be destroyed"
  end

  test "a compile_only submission where cafe scores non-zero is a real score mismatch, not silently passed" do
    dataset = build_live_dataset([2])
    problem = dataset.problem
    sample = { "task" => problem.name, "dataset_id" => dataset.id,
               "submissions" => [cpp_entry(2, cms_score: 0.0, compilation_outcome: "fail")] }

    Replay::ReplayGrader.stub :grade_sync, ->(*) { { points: 55.0, grader_comment: nil, status: "done" } } do
      report = C.run(problem, sample)
      assert_equal 1, report[:compile_only]
      assert_equal 0, report[:errored]
      assert_equal 1, report[:score_mismatch],
                   "cafe scoring where CMS recorded a compile failure is a genuine finding"
      assert_equal 0, report[:score_exact]
      assert_equal 1, report[:mismatch_details].size
      detail = report[:mismatch_details].first
      assert_equal :compile_only, detail[:kind]
      assert_in_delta 0.0, detail[:cms_score].to_f, 0.001
      assert_in_delta 55.0, detail[:cafe_points].to_f, 0.001
    end
  end

  test "a verdict-string difference with an identical score is verdict_only_diff and does not fail the task" do
    dataset = build_live_dataset([1]) # single testcase "01-01"
    problem = dataset.problem
    evaluations = { "01-01" => { "outcome" => 1.0, "text" => "Output is correct" } } # cms_gc = "P"
    sample = { "task" => problem.name, "dataset_id" => dataset.id,
               "submissions" => [cpp_entry(3, cms_score: 100.0, evaluations: evaluations)] }

    # grade_sync is stubbed, so no real Evaluation row is ever created for
    # the fresh submission -- cafe_verdict_string reads back "?" (no
    # evaluation row), a genuine per-testcase character difference against
    # CMS's "P", while the stubbed score matches CMS exactly.
    Replay::ReplayGrader.stub :grade_sync, ->(*) { { points: 100.0, grader_comment: nil, status: "done" } } do
      report = C.run(problem, sample)
      assert_equal 0, report[:score_mismatch], "a task must NOT fail on verdict-character noise alone"
      assert_equal 0, report[:errored]
      assert_equal 1, report[:verdict_only_diff]
      assert_equal 1, report[:score_exact]
      assert_equal 1, report[:verdict_only_details].size
      assert_empty report[:mismatch_details], "verdict-only diffs must not appear in the score-mismatch payload"
    end
  end

  test "a submission whose score differs is a score_mismatch and fails the task" do
    dataset = build_live_dataset([1])
    problem = dataset.problem
    evaluations = { "01-01" => { "outcome" => 1.0, "text" => "Output is correct" } }
    sample = { "task" => problem.name, "dataset_id" => dataset.id,
               "submissions" => [cpp_entry(4, cms_score: 100.0, evaluations: evaluations)] }

    Replay::ReplayGrader.stub :grade_sync, ->(*) { { points: 40.0, grader_comment: nil, status: "done" } } do
      report = C.run(problem, sample)
      assert_equal 1, report[:score_mismatch], "a genuine score disagreement must fail the task"
      assert_equal 0, report[:verdict_only_diff]
      assert_equal 0, report[:score_exact]
      assert_equal 1, report[:mismatch_details].size
      detail = report[:mismatch_details].first
      assert_equal :score_mismatch, detail[:kind]
      assert_in_delta 100.0, detail[:cms_score].to_f, 0.001
      assert_in_delta 40.0, detail[:cafe_points].to_f, 0.001
    end
  end
end
