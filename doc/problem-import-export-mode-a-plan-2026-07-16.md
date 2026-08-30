# Package 1 Capstone — Mode A Submission-Replay Validation Harness (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the hardened import/export path is behaviorally lossless on *real* submissions: export a problem, re-import it as a throwaway, replay a sample of the original's submissions through the real grading pipeline, and diff per-testcase results against the originals' stored grades.

**Architecture:** A `SubmissionReplay` orchestrator composes three units — a synchronous grader (`ReplayGrader`), a stratified sampler (`ReplaySampler`), and a pure diff classifier (`ReplayDiff`) — exposed via rake. Everything created is marked (`_rc_…` problem names, a `replay_bot` user) and destroyed on completion (`ensure`), with a `replay_purge` backstop. **Mode A is entirely cafe→cafe on the dev box; it never contacts the CMS server.** Spec: `doc/problem-import-export-design-2026-07-14.md` (§Validation harness — Mode A).

**Tech Stack:** Ruby 3.4.4 / Rails 8.0, minitest, the cafe judge engine (`app/engine/grader.rb` → Compiler/Evaluator/Scorer, isolate sandbox), Mercurial.

## Global Constraints

- **VCS is Mercurial.** Before EVERY commit run `hg log -r . --template '{activebookmark}\n'` — it MUST print `master`. If `chula_cp`, run `hg update master` first. Name explicit files in every `hg commit`. End commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **This is a dev-only diagnostic.** Nothing here runs against 10.44.7.1. No web UI. No changes to the grading engine, importer, or exporter — this harness only *drives* them.
- **Zero steady-state footprint.** Every problem/user/submission the harness creates is destroyed by end of run. Throwaway problems are named with the `_rc_` prefix (fits the 30-char `Problem.name` limit); replayed submissions belong to the `replay_bot` user. A mismatch never leaves data behind — cleanup is in an `ensure`.
- **Comparison baseline is the original's STORED grade** (decided with dae, cost reason). A guard skips submissions graded before the live dataset's `updated_at` (stale relative to the cloned dataset).
- **Benign-transition convention** (from CLAUDE.md / `doc/dataset-scoring-and-evaluation.md`): grading chars are `P` pass, `T` tle, `x` invalid/mle, `-` wrong, `s` partial. Only `T→P` and `x→P` are benign (machine speed/memory). Every other change is a real mismatch to investigate.
- Run tests with `bin/rails test <path>`. Curated default problem set: `ex00e2` (default eval + groups), `a58_proj_algo` (custom_cafe checker), `a57_m4_gaa` (group_min) — confirmed present in the dev DB 2026-07-15.

## File Structure

- `app/engine/replay/replay_grader.rb` — **create** (Task 13): synchronous single-submission grading via the real pipeline
- `app/engine/replay/replay_sampler.rb` — **create** (Task 14): stratified sampling + stale guard
- `app/engine/replay/replay_diff.rb` — **create** (Task 15): pure per-testcase transition classifier
- `app/engine/replay/submission_replay.rb` — **create** (Task 16): orchestrator (export→reimport→replay→diff→report→cleanup)
- `lib/tasks/replay.rake` — **create** (Task 17): `problems:replay_validate`, `problems:replay_purge`
- `test/engine/replay/replay_sampler_test.rb`, `replay_diff_test.rb`, `submission_replay_test.rb` — **create**
- `CHANGELOG.md` — **modify** (Task 17 only): one operator-facing bullet for the rake tasks

---

### Task 13 (SPIKE): Synchronous grading of one real submission

**Files:**
- Create: `app/engine/replay/replay_grader.rb`
- Scratch verification only (no committed test — this task's deliverable is the confirmed API + a working real grade)

**Interfaces:**
- Produces: `ReplayGrader.grade_sync(submission, dataset) → { points:, grader_comment:, status: }` — grades `submission` against `dataset` synchronously (no background worker), returns the terminal result. Task 16 depends on this exact signature.

**This is a spike: the goal is to confirm the grading incantation works on this box before building on it.** The suggested approach (enqueue + drain the real pipeline) is below; if isolation from unrelated queued jobs proves problematic, the fallback (direct engine calls replicating `Grader#process_job_*`) is acceptable — report which you used.

- [ ] **Step 1: Write the grader**

```ruby
# app/engine/replay/replay_grader.rb
module Replay
  # Grades a single submission synchronously through the REAL judge pipeline
  # (compile → evaluate → score), draining only this submission's jobs on a
  # dedicated isolate box. Dev diagnostic only; no background worker needed.
  module ReplayGrader
    module_function

    REPLAY_BOX_ID = (ENV['REPLAY_BOX_ID'] || 90).to_i   # avoid clashing with real workers' boxes
    REPLAY_WORKER_ID = 'replay'

    def grade_sync(submission, dataset)
      submission.add_judge_job(dataset)                 # enqueues the compile job (resets status)
      grader = Grader.new(REPLAY_WORKER_ID, REPLAY_BOX_ID)

      # Drain until this submission reaches a terminal status. The Grader takes
      # the oldest waiting job of its types; on a dev box with no live worker,
      # the only waiting jobs are the ones add_judge_job just created (compile),
      # which cascade into evaluate/score jobs.
      deadline = 600  # seconds, safety bound for one submission
      started = Time.zone.now
      loop do
        ran = grader.check_and_run_job
        submission.reload
        break if terminal?(submission.status)
        break unless ran || Job.has_waiting_job
        raise "replay grading exceeded #{deadline}s for sub ##{submission.id}" if (Time.zone.now - started) > deadline
      end

      { points: submission.points, grader_comment: submission.grader_comment, status: submission.status }
    end

    def terminal?(status)
      %w[done compilation_error grader_error].include?(status.to_s)
    end
  end
end
```

- [ ] **Step 2: Prove it on a real submission (scratch runner — NOT committed)**

Pick an existing problem with a graded submission and re-grade that same submission's source on a fresh submission, confirming the fresh grade matches the stored one:

```bash
bin/rails runner '
src = Submission.where.not(points: nil).where.not(grader_comment: [nil, ""]).joins(:problem).where(problems: {name: "ex00e2"}).order(id: :desc).first
raise "no graded submission for ex00e2" unless src
p = src.problem; ds = p.live_dataset
u = User.find_or_create_by!(login: "replay_bot") { |x| x.full_name = "Replay Bot"; x.password = SecureRandom.hex(12) }
clone = Submission.new(user: u, problem: p, language: src.language, source_filename: src.source_filename, submitted_at: Time.zone.now, tag: :default)
clone.source = src.source
clone.save(validate: false)
r = Replay::ReplayGrader.grade_sync(clone, ds)
puts "stored:  points=#{src.points} gc=#{src.grader_comment.inspect}"
puts "replay:  points=#{r[:points]} gc=#{r[:grader_comment].inspect} status=#{r[:status]}"
Job.where(arg: clone.id).delete_all   # judge jobs have no FK to the submission
clone.destroy                         # clean up the scratch submission
'
```

Expected: `replay` points/grader_comment equal (or benignly differ from) `stored`. If grading errors (isolate box perms, missing compiler), capture the exact error.

- [ ] **Step 3: Decision point**

- If the grade succeeded and matches: **DONE.** Report the confirmed `grade_sync` return shape and any deviation from the code above (e.g., you needed a different box id, or the drain condition needed adjusting). Commit `app/engine/replay/replay_grader.rb`:

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add app/engine/replay/replay_grader.rb
hg commit app/engine/replay/replay_grader.rb -m "feat(replay): synchronous single-submission grader for validation harness

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- If grading is **not possible on this box** (isolate/cgroup/permission failure that isn't a quick fix): STOP and report **BLOCKED** with the exact failure. Do not fake it. The controller will decide whether to make the real run an operator step elsewhere while still building the (unit-testable) rest.

---

### Task 14: Stratified sampler with stale guard

**Files:**
- Create: `app/engine/replay/replay_sampler.rb`
- Test: `test/engine/replay/replay_sampler_test.rb`

**Interfaces:**
- Produces: `Replay::ReplaySampler.sample(problem, limit: 100) → { submissions: [Submission], skipped_stale: Integer, buckets: {zero:, partial:, full:} }`. Task 16 consumes `.submissions` and reports the rest.

- [ ] **Step 1: Write failing tests**

```ruby
# test/engine/replay/replay_sampler_test.rb
require "test_helper"

class Replay::ReplaySamplerTest < ActiveSupport::TestCase
  # Build a problem whose live dataset was updated at a known time, plus
  # submissions in each score bucket, some graded before that time (stale).
  def build(dataset_updated_at:)
    problem = Problem.create!(name: "smp_#{SecureRandom.hex(3)}", full_name: "Sampler")
    ds = Dataset.create!(problem: problem, name: "D1")
    problem.update!(live_dataset: ds)
    ds.update_column(:updated_at, dataset_updated_at)
    problem
  end

  def add_sub(problem, points:, graded_at:)
    s = Submission.new(user: users(:admin), problem: problem, language: languages(:cpp),
                       source_filename: "a.cpp", submitted_at: graded_at, points: points)
    s.source = "int main(){}"
    s.save!(validate: false)
    s.update_columns(points: points, graded_at: graded_at)
    s
  end

  test "stratifies across buckets and skips stale submissions" do
    cutoff = Time.zone.parse("2026-01-01 00:00")
    p = build(dataset_updated_at: cutoff)
    # fresh (graded after cutoff)
    add_sub(p, points: 0,   graded_at: cutoff + 1.day)
    add_sub(p, points: 50,  graded_at: cutoff + 1.day)
    add_sub(p, points: 100, graded_at: cutoff + 1.day)
    # stale (graded before cutoff) — must be skipped
    add_sub(p, points: 100, graded_at: cutoff - 1.day)

    out = Replay::ReplaySampler.sample(p, limit: 100)
    assert_equal 1, out[:skipped_stale]
    assert_equal 3, out[:submissions].size
    assert_equal({ zero: 1, partial: 1, full: 1 }, out[:buckets])
  end

  test "limit is respected via round-robin across buckets" do
    cutoff = Time.zone.parse("2026-01-01 00:00")
    p = build(dataset_updated_at: cutoff)
    6.times { add_sub(p, points: 0,   graded_at: cutoff + 1.day) }
    6.times { add_sub(p, points: 100, graded_at: cutoff + 1.day) }
    out = Replay::ReplaySampler.sample(p, limit: 4)
    assert_equal 4, out[:submissions].size
    pts = out[:submissions].map { |s| s.points.to_f }
    # round-robin should pull from both buckets, not 4 from one
    assert pts.count(0.0).between?(1, 3), "expected a mix of buckets, got #{pts.inspect}"
  end
end
```

- [ ] **Step 2: Run — expect FAIL** (`Replay::ReplaySampler` undefined)

Run: `bin/rails test test/engine/replay/replay_sampler_test.rb`

- [ ] **Step 3: Implement**

```ruby
# app/engine/replay/replay_sampler.rb
module Replay
  module ReplaySampler
    module_function

    # Up to `limit` of the problem's graded submissions, stratified across
    # zero / partial / full score buckets. Skips submissions graded before the
    # live dataset's updated_at (their stored grade predates the dataset we clone).
    def sample(problem, limit: 100)
      ds = problem.live_dataset
      cutoff = ds&.updated_at
      graded = problem.submissions.where.not(points: nil).order(:id).to_a
      fresh, stale = graded.partition do |s|
        cutoff.nil? || s.graded_at.nil? || s.graded_at >= cutoff
      end

      max_pts = fresh.map { |s| s.points.to_f }.max || 0.0
      buckets = { zero: [], partial: [], full: [] }
      fresh.each do |s|
        pts = s.points.to_f
        key = if pts <= 0 then :zero
              elsif max_pts.positive? && pts >= max_pts then :full
              else :partial
              end
        buckets[key] << s
      end

      picked = round_robin(buckets.values, limit)
      { submissions: picked, skipped_stale: stale.size,
        buckets: buckets.transform_values(&:size) }
    end

    # Interleave lists so `limit` picks are spread across non-empty buckets.
    def round_robin(lists, limit)
      lists = lists.map(&:dup)
      result = []
      i = 0
      while result.size < limit && lists.any?(&:any?)
        list = lists[i % lists.size]
        result << list.shift if list.any?
        i += 1
      end
      result
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (no changelog — internal unit)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add app/engine/replay/replay_sampler.rb test/engine/replay/replay_sampler_test.rb
hg commit app/engine/replay/replay_sampler.rb test/engine/replay/replay_sampler_test.rb -m "feat(replay): stratified submission sampler with stale-grade guard

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 15: Per-testcase diff classifier (pure)

**Files:**
- Create: `app/engine/replay/replay_diff.rb`
- Test: `test/engine/replay/replay_diff_test.rb`

**Interfaces:**
- Produces: `Replay::ReplayDiff.classify(orig_gc, orig_points, new_gc, new_points) → { verdict: :exact|:benign|:mismatch|:structural, positions: [{i:, from:, to:, kind:}], points: [orig, new], note?: }`. Task 16 consumes `verdict` and `positions`.

- [ ] **Step 1: Write failing tests**

```ruby
# test/engine/replay/replay_diff_test.rb
require "test_helper"

class Replay::ReplayDiffTest < ActiveSupport::TestCase
  D = Replay::ReplayDiff

  test "identical grading is exact" do
    r = D.classify("PPP-P", 80, "PPP-P", 80)
    assert_equal :exact, r[:verdict]
    assert_empty r[:positions]
  end

  test "only T->P and x->P upgrades are benign" do
    r = D.classify("TxP", 33, "PPP", 100)
    assert_equal :benign, r[:verdict]
    assert_equal 2, r[:positions].size
    assert r[:positions].all? { |p| p[:kind] == :benign }
  end

  test "P->T (or any other change) is a mismatch" do
    r = D.classify("PPP", 100, "PPT", 66)
    assert_equal :mismatch, r[:verdict]
    assert_equal({ i: 2, from: "P", to: "T", kind: :mismatch }, r[:positions].first)
  end

  test "wrong-answer flip is a mismatch, not benign" do
    r = D.classify("P-P", 66, "PPP", 100)   # -  ->  P is NOT in the benign set
    assert_equal :mismatch, r[:verdict]
  end

  test "different lengths are structural" do
    r = D.classify("PPP", 100, "PP", 100)
    assert_equal :structural, r[:verdict]
    assert_match(/length differs/, r[:note])
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/engine/replay/replay_diff_test.rb`

- [ ] **Step 3: Implement**

```ruby
# app/engine/replay/replay_diff.rb
module Replay
  # Pure classifier: compares a stored grading string against a fresh re-grade.
  # Only T->P and x->P (machine speed / memory) are benign; everything else is a
  # real mismatch. Grading chars: P pass, T tle, x invalid/mle, - wrong, s partial.
  module ReplayDiff
    module_function

    BENIGN = [%w[T P], %w[x P]].freeze

    def classify(orig_gc, orig_points, new_gc, new_points)
      orig_gc = orig_gc.to_s
      new_gc  = new_gc.to_s
      if orig_gc.length != new_gc.length
        return { verdict: :structural, positions: [], points: [orig_points, new_points],
                 note: "grader_comment length differs (#{orig_gc.length} vs #{new_gc.length})" }
      end

      positions = []
      orig_gc.chars.each_with_index do |from, i|
        to = new_gc[i]
        next if from == to
        kind = BENIGN.include?([from, to]) ? :benign : :mismatch
        positions << { i: i, from: from, to: to, kind: kind }
      end

      verdict = if positions.empty? then :exact
                elsif positions.all? { |p| p[:kind] == :benign } then :benign
                else :mismatch
                end
      { verdict: verdict, positions: positions, points: [orig_points, new_points] }
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (no changelog)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add app/engine/replay/replay_diff.rb test/engine/replay/replay_diff_test.rb
hg commit app/engine/replay/replay_diff.rb test/engine/replay/replay_diff_test.rb -m "feat(replay): pure per-testcase grading-diff classifier

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 16: Orchestrator — export → reimport → replay → diff → report → cleanup

**Files:**
- Create: `app/engine/replay/submission_replay.rb`
- Test: `test/engine/replay/submission_replay_test.rb`

**Interfaces:**
- Consumes: `ReplayGrader.grade_sync(sub, dataset, deadline: 600)` (T13, confirmed shape `{points:, grader_comment:, status:}`), `ReplaySampler.sample` (T14), `ReplayDiff.classify` (T15), `ProblemExporter`, `ProblemImporter`.
- Produces: `Replay::SubmissionReplay.run(problem, limit: 100) → report Hash` (see shape in Step 3). `Replay::SubmissionReplay.purge! → Integer` (destroys all `_rc_` problems + replay_bot submissions + the replay grader_process; returns problem count). `Replay::SubmissionReplay::RC_PREFIX = '_rc_'`.

**Spike findings from Task 13 that shape this task:**
- `grade_sync` needs a **running dev server at localhost:3000** (compiler/evaluator fetch assets + upload compiled files over HTTP). The integration test below is therefore **opt-in** (guarded on `ENV['REPLAY_LIVE']`); the real exercise is Task 17's capstone with a server up.
- On this box **only C++ grades cleanly** (cgroup-v2 isn't configured, so python/java/go/etc. return `grader_error`). A fresh `grader_error` is an **environment** limitation, not an import/export defect — the orchestrator buckets it as `:errored` (reported, excluded from the mismatch verdict), never as `:mismatch`.

- [ ] **Step 1: Write the failing integration test**

```ruby
# test/engine/replay/submission_replay_test.rb
require "test_helper"
require "tmpdir"

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
    sol = File.read(Dir[Rails.root.join("test","problem_examples","fibo","model_solutions","**","*.cpp")].first)
    seed = Submission.new(user: users(:admin), problem: problem, language: languages(:cpp),
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
    assert_empty Problem.where("name LIKE ?", "#{Replay::SubmissionReplay::RC_PREFIX}%")
  end
end
```

- [ ] **Step 2: Run — expect FAIL** (`Replay::SubmissionReplay` undefined; or skip if no judge)

Run: `bin/rails test test/engine/replay/submission_replay_test.rb`

- [ ] **Step 3: Implement**

```ruby
# app/engine/replay/submission_replay.rb
module Replay
  # Cafe->cafe behavioral validation of the import/export path. Exports a
  # problem, re-imports it as a throwaway (_rc_ prefix), replays a sample of the
  # original's submissions through the real grader, and diffs each fresh grade
  # against the original's STORED grade. Everything created is destroyed on exit.
  # Dev diagnostic only — never touches CMS.
  module SubmissionReplay
    module_function

    RC_PREFIX = '_rc_'

    def replay_bot
      User.find_or_create_by!(login: 'replay_bot') do |u|
        u.full_name = 'Replay Bot (import/export validation)'
        u.password = SecureRandom.hex(16)
      end
    end

    def run(problem, limit: 100)
      sample = ReplaySampler.sample(problem, limit: limit)
      clone = nil
      report = { problem: problem.name, replayed: 0, skipped_stale: sample[:skipped_stale],
                 buckets: sample[:buckets], exact: 0, benign: 0, mismatch: 0,
                 structural: 0, errored: 0, mismatch_details: [], error_details: [] }
      begin
        clone = import_clone(problem)
        bot = replay_bot
        sample[:submissions].each do |orig|
          fresh = build_submission(bot, clone, orig)
          res = ReplayGrader.grade_sync(fresh, clone.live_dataset)
          diff = ReplayDiff.classify(orig.grader_comment, orig.points, res[:grader_comment], res[:points])
          tally(report, diff, orig, res)
          report[:replayed] += 1
        ensure
          # Judge Job rows reference the submission by integer `arg` (no FK), so
          # they are NOT cascade-destroyed with the problem — delete them here.
          Job.where(arg: fresh.id).delete_all if fresh
        end
      ensure
        clone&.destroy   # cascades datasets/testcases/submissions/evaluations + purges blobs
      end
      report
    end

    # Export `problem` to a temp dir and re-import it as a fresh _rc_ problem.
    def import_clone(problem)
      Dir.mktmpdir("replay") do |dump|
        ProblemExporter.new.export_problem_to_dir(problem, base_dir: dump, zip: false)
        exported = File.join(dump, problem.name.parameterize)
        pi = ProblemImporter.new
        pi.import_dataset_from_dir(exported, "#{RC_PREFIX}#{SecureRandom.hex(6)}",
                                   full_name: "replay of #{problem.name}", user: replay_bot,
                                   do_solutions: false)
        pi.problem
      end
    end

    def build_submission(bot, clone, orig)
      s = Submission.new(user: bot, problem: clone, language: orig.language,
                         source_filename: orig.source_filename, submitted_at: Time.zone.now, tag: :default)
      s.source = orig.source
      s.save!(validate: false)   # replaying already-valid sources; skip submit-auth validation
      s
    end

    def tally(report, diff, orig, res)
      # A fresh grader_error while the stored grade was a real result is an
      # ENVIRONMENT limitation (e.g. sandbox/cgroup unavailable for some
      # languages on this box), not an import/export defect — bucket apart and
      # exclude from the pass/fail verdict.
      if res[:status].to_s == 'grader_error'
        report[:errored] += 1
        report[:error_details] << { orig_submission_id: orig.id, language: orig.language&.name,
                                    new_status: res[:status], new_gc: res[:grader_comment] }
        return
      end
      report[diff[:verdict]] += 1
      return unless %i[mismatch structural].include?(diff[:verdict])
      report[:mismatch_details] << {
        orig_submission_id: orig.id, verdict: diff[:verdict],
        orig_points: orig.points, new_points: res[:points],
        orig_gc: orig.grader_comment, new_gc: res[:grader_comment],
        positions: diff[:positions], note: diff[:note]
      }
    end

    # Destroy every throwaway artifact (backstop for interrupted runs).
    def purge!
      Submission.joins(:user).where(users: { login: 'replay_bot' }).find_each do |s|
        Job.where(arg: s.id).delete_all   # judge jobs have no FK to the submission
        s.destroy
      end
      # the dedicated replay grader_process row (created by ReplayGrader)
      GraderProcess.where(box_id: ReplayGrader::REPLAY_BOX_ID,
                          worker_id: ReplayGrader::REPLAY_WORKER_ID).delete_all
      scope = Problem.where("name LIKE ?", "#{RC_PREFIX}%")
      count = scope.count
      scope.find_each(&:destroy)
      count
    end
  end
end
```

Note: `report[:mismatch]`/`report[:structural]` are counted; a `:structural` verdict also lands in `mismatch_details`. The gate in Step 1 asserts `report[:mismatch] == 0`; treat `structural > 0` as a failure too when reporting (Task 17 rolls both into the pass/fail line).

- [ ] **Step 4: Run — expect PASS (or skip if judge unavailable)**

Run: `bin/rails test test/engine/replay/submission_replay_test.rb`
If it skips (no judge in this env), note that in the report; the real exercise is Task 17's capstone run.

- [ ] **Step 5: Commit** (no changelog — the operator surface lands in Task 17)

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add app/engine/replay/submission_replay.rb test/engine/replay/submission_replay_test.rb
hg commit app/engine/replay/submission_replay.rb test/engine/replay/submission_replay_test.rb -m "feat(replay): submission-replay orchestrator with guaranteed cleanup

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 17: Rake surface, purge, and the real capstone run

**Files:**
- Create: `lib/tasks/replay.rake`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Write the rake tasks**

```ruby
# lib/tasks/replay.rake
namespace :problems do
  desc "Validate import/export by replaying submissions (cafe->cafe, dev only). " \
       "Usage: rake problems:replay_validate[ex00e2+a58_proj_algo,100]"
  task :replay_validate, %i[names limit] => :environment do |_t, args|
    names = (args[:names] || "ex00e2+a58_proj_algo+a57_m4_gaa").split("+")
    limit = (args[:limit] || 100).to_i
    puts "Replay validation (dev, no CMS contact). Cleanup backstop if interrupted:"
    puts "  bin/rails 'problems:replay_purge'\n\n"

    overall_ok = true
    names.each do |name|
      problem = Problem.find_by(name: name)
      unless problem
        puts "SKIP #{name}: not found"; next
      end
      report = Replay::SubmissionReplay.run(problem, limit: limit)
      bad = report[:mismatch] + report[:structural]   # errored is env, NOT a failure
      overall_ok &&= bad.zero?
      puts format("%-22s replayed=%-4d stale=%-4d exact=%-4d benign=%-4d MISMATCH=%-3d STRUCT=%-3d errored=%-3d buckets=%s",
                  name, report[:replayed], report[:skipped_stale], report[:exact],
                  report[:benign], report[:mismatch], report[:structural], report[:errored], report[:buckets].inspect)
      report[:mismatch_details].each do |d|
        puts "   ! sub ##{d[:orig_submission_id]} #{d[:verdict]} pts #{d[:orig_points]}->#{d[:new_points]} " \
             "gc #{d[:orig_gc].inspect}->#{d[:new_gc].inspect}"
      end
      if report[:errored].positive?
        langs = report[:error_details].group_by { |e| e[:language] }.transform_values(&:size)
        puts "   ~ #{report[:errored]} not gradable in this env (cgroup/lang): #{langs.inspect}"
      end
    end
    puts "\n#{overall_ok ? 'PASS — no non-benign differences' : 'FAIL — investigate mismatches above'}"
  end

  desc "Purge all replay-validation artifacts (_rc_ problems + replay_bot submissions)."
  task replay_purge: :environment do
    n = Replay::SubmissionReplay.purge!
    puts "Purged #{n} throwaway _rc_ problems and all replay_bot submissions."
  end
end
```

- [ ] **Step 2: Verify the tasks load**

Run: `bin/rails -T problems:replay`
Expected: both `problems:replay_validate` and `problems:replay_purge` listed.

- [ ] **Step 3: The capstone real run (dev box)**

`grade_sync` needs a **running dev server at localhost:3000** (spike finding). Start one if not already up, in the background, and confirm it responds before running:

```bash
# start dev server if needed (background); the app runs on chula_cp per repo convention,
# but grading only needs the web app + assets, so master is fine for this diagnostic
(bin/rails server -d -p 3000 || bin/rails server -p 3000 &) ; sleep 8
curl -sSf -o /dev/null http://localhost:3000/ && echo "server up" || echo "SERVER NOT UP — grading will fail"
```

Then run the validation on the curated set at a small limit first, then the target 100:

```bash
bin/rails "problems:replay_validate[ex00e2,10]"     # smoke — one problem, tiny sample
bin/rails "problems:replay_validate[ex00e2+a58_proj_algo+a57_m4_gaa,100]"
```

Expected: `PASS — no non-benign differences`. Record the full output in the report.
- A `MISMATCH`/`STRUCT` on any problem is a **real finding** about the import/export path (or a stale grade the guard missed) — capture the detail lines and report them; do NOT silence them.
- An `errored=N (cgroup/lang)` line is the **environment limitation** the spike found (non-C++ languages can't grade here); it does NOT fail the run. Note the languages affected. Broadening this (cgroup-v2 delegation) is an operator/backlog item, not part of this task. If a whole curated problem is dominated by `errored`, the C++ subset still provides the losslessness proof; note the reduced coverage.
- If you started the dev server in this step, **stop it afterward** (`bin/rails server` PID or `pkill -f "puma.*3000"`) so it doesn't linger.

- [ ] **Step 4: Confirm zero residue**

```bash
bin/rails "problems:replay_purge"    # should report 0 if the run cleaned up after itself
bin/rails runner 'puts Problem.where(%q{name LIKE ?}, "_rc_%").count; puts Submission.joins(:user).where(users: {login: "replay_bot"}).count'
```
Expected: `Purged 0 …`, then `0` and `0`.

- [ ] **Step 5: Commit with changelog**

CHANGELOG bullet under `[Unreleased]` → `### Added`:

```markdown
- **`problems:replay_validate` rake task** — validates the problem import/export
  path by re-importing a problem and replaying a stratified sample of its
  submissions through the grader, diffing per-testcase results against the
  originals' stored grades (only `T→P`/`x→P` treated as benign). Dev diagnostic;
  self-cleaning, with `problems:replay_purge` as a backstop.
```

```bash
hg log -r . --template '{activebookmark}\n'   # must print: master
hg add lib/tasks/replay.rake
hg commit lib/tasks/replay.rake CHANGELOG.md -m "feat(replay): rake surface for import/export submission-replay validation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Notes for the executor

- **Task 13 is the gate.** If synchronous grading can't run on this box, everything downstream that *grades* (T16 integration test, T17 capstone) degrades to "built + unit-tested, real run deferred to an environment with a judge." The pure units (T14 sampler, T15 diff) are unaffected and must still pass. Surface this clearly rather than forcing green.
- **Determinism caveat (vs-stored baseline):** a genuine MISMATCH can mean (a) an import/export defect, (b) the original's stored grade predates a live-dataset change the stale-guard missed, or (c) real judge nondeterminism. Report the detail lines; triage is a human call.
- **`ProblemImporter#import_dataset_from_dir`** signature (from Package 1): keyword `user:` exists; `do_solutions:` defaults true — the orchestrator passes `do_solutions: false` (replaying submissions, not re-importing the source problem's model solutions, keeps the clone lean).
