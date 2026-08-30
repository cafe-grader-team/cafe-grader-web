require "test_helper"
require "tmpdir"
require "minitest/mock"

class Replay::SubmissionReplayTest < ActiveSupport::TestCase
  # A tiny real problem: import the fibo_minimal example, attach one model
  # solution, grade it once so it has a stored grade, then replay.
  # NOTE: this test actually grades via the judge engine. If grading is
  # unavailable in this env it will be skipped with a clear message (the
  # unit pieces — sampler/diff — are covered by their own tests).
  test "replay of a losslessly round-tripped problem reports zero mismatches and cleans up" do
    # Opt-in: needs a running dev server at :3000 + isolate (grade_sync uses HTTP).
    # The unit pieces (sampler/diff) are covered by their own tests; the real
    # end-to-end exercise is Task 17's capstone run.
    skip "set REPLAY_LIVE=1 with a dev server + judge to run this" unless ENV["REPLAY_LIVE"] == "1"

    pi = ProblemImporter.new
    pi.import_dataset_from_dir(Rails.root.join("test", "problem_examples", "fibo").to_s,
                              "rc_src_#{SecureRandom.hex(3)}", user: users(:admin))
    problem = pi.problem
    # give it one graded submission (a correct C++ solution ships in the fixture)
    sol = File.read(Dir[Rails.root.join("test", "problem_examples", "fibo", "model_solutions", "**", "*.cpp")].first)
    seed = Submission.new(user: users(:admin), problem: problem, language: languages(:Language_cpp),
                          source_filename: "sol.cpp", submitted_at: Time.zone.now)
    seed.source = sol
    seed.save!(validate: false)
    Replay::ReplayGrader.grade_sync(seed, problem.live_dataset)
    seed.reload
    skip "seed did not grade (env)" if seed.points.nil?

    before = Problem.count
    report = Replay::SubmissionReplay.run(problem, limit: 10)

    assert_equal 0, report[:mismatch], "expected no non-benign mismatches: #{report[:mismatch_details].inspect}"
    assert report[:replayed] >= 1
    assert_equal before, Problem.count, "throwaway _rc_ problem must be destroyed"
    assert_empty Problem.where("name LIKE ?",
                               "#{Problem.sanitize_sql_like(Replay::SubmissionReplay::RC_PREFIX)}%")
  end

  test "run destroys the clone and cleans up jobs even when grading raises" do
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(Rails.root.join("test", "problem_examples", "fibo").to_s,
                              "rcsrc_#{SecureRandom.hex(3)}", user: users(:admin))
    problem = pi.problem
    seed = Submission.new(user: users(:admin), problem: problem, language: languages(:Language_cpp),
                          source_filename: "a.cpp", submitted_at: Time.zone.now)
    seed.source = "int main(){}"
    seed.save!(validate: false)
    # +1.minute, not Time.zone.now: submissions.graded_at is a bare `datetime`
    # (whole-second precision) while datasets.updated_at is `datetime(6)`
    # (microseconds). A same-second graded_at truncates down and can land
    # BEFORE the dataset's fractional updated_at, tripping ReplaySampler's
    # staleness cutoff (graded_at >= dataset.updated_at) nondeterministically
    # -- this was observed to fail ~40% of runs before the buffer was added.
    seed.update_columns(points: 100, graded_at: 1.minute.from_now)

    before_problems = Problem.count

    Replay::ReplayGrader.stub :grade_sync, ->(*) { raise "boom" } do
      report = Replay::SubmissionReplay.run(problem, limit: 5)
      assert report[:errored] >= 1, "a raised grade must be bucketed as errored, not lost"
    end

    assert_equal before_problems, Problem.count, "throwaway _rc_ clone must be destroyed"
    assert_empty Problem.where("name LIKE ?",
                               "#{Problem.sanitize_sql_like(Replay::SubmissionReplay::RC_PREFIX)}%")
    assert_equal 0, Submission.joins(:user).where(users: { login: "replay_bot" }).count,
                 "no replay_bot submissions may remain"
  end

  test "a fresh compile/grader error on a gradable language is bucketed suspect and fails the verdict" do
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(Rails.root.join("test", "problem_examples", "fibo").to_s,
                              "rcsrc_#{SecureRandom.hex(3)}", user: users(:admin))
    problem = pi.problem
    seed = Submission.new(user: users(:admin), problem: problem, language: languages(:Language_cpp),
                          source_filename: "a.cpp", submitted_at: Time.zone.now)
    seed.source = "int main(){}"
    seed.save!(validate: false)
    # Original graded cleanly (status :done). C++ is in GRADABLE_LANGS, so a
    # fresh compilation_error here is SUSPECT (e.g. a lost checker surfacing
    # as grader_error) -- it must NOT be silently bucketed as environment
    # noise (errored), and it must fail the verdict (mismatch_details non-empty).
    seed.update_columns(status: Submission.statuses[:done], points: 100, graded_at: 1.minute.from_now)

    Replay::ReplayGrader.stub :grade_sync,
                              ->(*) { { points: 0, grader_comment: "Compilation error", status: "compilation_error" } } do
      report = Replay::SubmissionReplay.run(problem, limit: 5)
      assert_equal 0, report[:mismatch]
      assert_equal 0, report[:structural]
      assert_equal 0, report[:errored]
      assert report[:suspect] >= 1
      assert_not_empty report[:mismatch_details]
    end

    assert_empty Problem.where("name LIKE ?",
                               "#{Problem.sanitize_sql_like(Replay::SubmissionReplay::RC_PREFIX)}%")
  end

  test "tally buckets a fresh compile/grader error on a non-gradable language as errored, not suspect" do
    # Pascal ("pas") is not in GRADABLE_LANGS (cpp,c) -- on this box only
    # C/C++ grade reliably (cgroup unconfigured for other toolchains), so a
    # fresh error on Pascal is an environment gap, not a real regression, and
    # must stay bucketed as errored (excluded from the verdict).
    #
    # NOTE: `run` now calls ReplaySampler.sample(..., languages: GRADABLE_LANGS),
    # so a non-gradable-language submission is never sampled in the first
    # place -- this scenario can no longer occur end-to-end. Exercise tally()
    # directly to keep its defensive branch covered.
    problem = Problem.create!(name: "smp_#{SecureRandom.hex(3)}", full_name: "Sampler")
    orig = Submission.new(user: users(:admin), problem: problem, language: languages(:Language_pas),
                          source_filename: "a.pas", submitted_at: Time.zone.now)
    orig.source = "begin end."
    orig.save!(validate: false)
    orig.update_columns(status: Submission.statuses[:done], points: 100)

    report = { errored: 0, suspect: 0, mismatch: 0, structural: 0, mismatch_details: [], error_details: [] }
    res = { points: 0, grader_comment: "Compilation error", status: "compilation_error" }

    Replay::SubmissionReplay.tally(report, {}, orig, res)

    assert_equal 0, report[:mismatch]
    assert_equal 0, report[:structural]
    assert_equal 0, report[:suspect]
    assert report[:errored] >= 1
  end

  test "run skips (does not crash) when export hits a missing ActiveStorage blob" do
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(Rails.root.join("test", "problem_examples", "fibo").to_s,
                              "rcsrc_#{SecureRandom.hex(3)}", user: users(:admin))
    problem = pi.problem
    seed = Submission.new(user: users(:admin), problem: problem, language: languages(:Language_cpp),
                          source_filename: "a.cpp", submitted_at: Time.zone.now)
    seed.source = "int main(){}"
    seed.save!(validate: false)
    seed.update_columns(status: Submission.statuses[:done], points: 100, graded_at: 1.minute.from_now)

    # No stub_any_instance in stock minitest (no mocha in this Gemfile) --
    # stub the module method `run` actually calls instead of the exporter
    # instance method, exercising the same begin/rescue in `run`.
    Replay::SubmissionReplay.stub :import_clone, ->(*) { raise ActiveStorage::FileNotFoundError, "missing blob" } do
      report = Replay::SubmissionReplay.run(problem, limit: 5)
      assert report[:skipped], "must skip, not crash"
      assert_match(/sync:problem/, report[:skip_reason])
    end

    assert_empty Problem.where("name LIKE ?",
                               "#{Problem.sanitize_sql_like(Replay::SubmissionReplay::RC_PREFIX)}%")
  end
end
