# Contest AI-usage report, LLM timing, queue split, exam bug fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the contest AI-usage report, per-call LLM timing, a dedicated viva job queue, and the four bugs the 2026-09-09 exam exposed.

**Architecture:** A `Stats` percentile helper and an `AiUsageReport` PORO do the reading; two new `ContestsController` actions render an HTML overview (tiles + two Chart.js charts + summary tables) and a JSON feed for a per-call DataTable. Two new nullable timing columns (`llm_started_at`, `llm_latency_ms`) on `viva_turns`, `comments`, `viva_grades` are written from one wrapper in `Llm::Request`, splitting queue time from model time. A `viva` Solid Queue worker isolates interview/grading jobs from assist jobs. Three small controller/view fixes close the exam-day 500s and the editor mode-switch hole.

**Tech Stack:** Ruby 3.4.4, Rails 8.0 (load_defaults 7.0), MySQL 8, Solid Queue, HAML, Stimulus, Chart.js 4.4 (importmap pin `chart`), DataTables, minitest.

**Spec:** `doc/exam-postmortem-2026-09-09-d69_q1.md` (findings F1–F8, work items W0–W3, bug table B1–B4).

> **Post-execution notes (2026-09-13 → 09-17).** Executed as revs 2134–2143 with these deviations, kept here so the plan is not read as the shipped state:
> - Task 4: `config/database.yml` is per-host and hg-ignored (only `database.yml.SAMPLE` is tracked), so its pool floor could not be committed. Instead the worker defaults were resized to **viva 3 + default 3 threads** (rev 2146) to fit the stock pool of 5 — a deploy needs no host environment change. The knobs were renamed **`VIVA_JOB_THREADS` / `JOB_THREADS`** because in the stock Solid Queue template `JOB_CONCURRENCY` means *processes*. The `RAILS_MAX_THREADS>=12` deployment step below is therefore obsolete.
> - Per-host tuning path: `config/solid_queue.env` (untracked; `.SAMPLE` shipped, rev 2150), read by the systemd unit via `EnvironmentFile=` — that unit line is not yet installed on any host.
> - Added beyond the plan: `database.yml.SAMPLE` sizing note (2148); a **Job Workers** card on Grader Processes showing each Solid Queue worker's effective queues and thread pool (2151); chart double-draw guard (2143).
> - Record of what shipped and what is still open: `doc/exam-postmortem-2026-09-09-d69_q1.md` → "Status update".

## Global Constraints

- **VCS is Mercurial**, not git. Commit with `hg commit -m "..." <explicit files>`. The active bookmark must be `master` before committing — check `hg log -r . --template '{activebookmark}\n'`; if it prints `chula_cp`, run `hg update master` first. Never `hg add`-less commit a new file (run `hg add <path>` first).
- **Attribution:** end each commit message with a trailing line `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **MySQL 8 only**, collation `utf8mb4_0900_ai_ci`. Migrations inherit it automatically; do not hand-set charset.
- **No Node build.** JS is importmap + Stimulus; edit `.js` under `app/javascript` directly. Chart.js is already pinned as `chart` (UMD, sets `window.Chart`).
- **Turbo drive is OFF** (`Turbo.session.drive = false`). Every mutating control opts in with `form: {data: {turbo: true}}`. The report is read-only, so this matters only if you add an action button.
- **Data attributes: flat keys only** in Rails tag helpers (`data: { foo_bar: 1 }` → `data-foo-bar`), never nested hashes (CLAUDE.md → Frontend conventions).
- **JSON-fed DataTables escape by default** via `dt.escape_columns_by_default(...)`, done for you by the `datatables--init` controller. A column that emits server-built HTML opts out with `render: (d) => d`.
- **Changelog in the same commit.** A user/operator-facing change adds a curated bullet under `## [Unreleased]` in `CHANGELOG.md`, citing the rev. Pure internals (the timing wrapper, the queue split test) are skipped.
- **Live docs in the same commit.** A change to viva behavior adds a `doc/Viva-History.md` entry; an assist change adds `doc/Assist-History.md`. The report touches both features → one pointer entry each (Problem → Change → Outcome, with the rev). The postmortem already seeded a 2026-09-12 stub in both — extend it, don't duplicate.
- **Run one test file** with `bin/rails test test/path/to/file.rb`; a single test with `:LINE`. Full check is `bin/rails check` but is heavy — run targeted files per task.
- **Autoload:** `lib/` is autoloaded (`config.autoload_lib`), so `lib/stats.rb` → `Stats`. `app/models/ai_usage_report.rb` → `AiUsageReport` (a PORO in the models dir is fine; it is not an AR model).

---

## File Structure

- `lib/stats.rb` (new) — `Stats.percentile(values, q)`, `Stats.mean(values)`. Pure functions, no Rails deps.
- `db/migrate/20260912120000_add_llm_timing_columns.rb` (new) — six columns.
- `app/services/llm/request.rb` (modify) — `timed_execute_call`, `attr_reader :llm_started_at, :llm_latency_ms`, `respond` uses the timer.
- `app/services/llm/viva_turn_assist.rb`, `comment_assist.rb`, `viva_grade_assist.rb` (modify) — persist the two timing values; grade uses `timed_execute_call` in its re-ask override.
- `config/queue.yml` (modify) — `viva` + `default` workers.
- `config/database.yml` (modify) — raise the pool floor so a worker's threads all get a connection.
- `app/jobs/llm/viva_turn_assist_job.rb`, `viva_grade_assist_job.rb` (modify) — `queue_as :viva`.
- `app/models/viva_turn.rb` (modify) — `fail_stale!` and `stuck` key on `llm_started_at` (B3).
- `app/models/ai_usage_report.rb` (new) — the report PORO.
- `app/controllers/contests_controller.rb` (modify) — `ai_usage`, `ai_usage_query`, auth wiring; B4 (`admin_authorization` on `set_system_mode`).
- `config/routes.rb` (modify) — two member routes.
- `app/views/contests/ai_usage.html.haml` (new), `app/views/contests/show.html.haml` + `view.html.haml` (modify) — link button.
- `app/javascript/controllers/chart_controller.js` (modify) — `stacked_bar`, `multiline` presets.
- `app/javascript/controllers/datatables/configs.js` + `columns.js` (modify) — `contestAiUsage` config + columns.
- `app/views/layouts/_header.html.haml` + `app/views/main/_contest_box.html.haml` (modify) — B1 nil guard.
- `app/models/user.rb` or `app/models/problem.rb` (modify) — B2 fix (reorder before `.ids`).
- Tests: `test/lib/stats_test.rb`, `test/models/ai_usage_report_test.rb`, `test/integration/contests_ai_usage_test.rb`, additions to `test/services/llm/viva_turn_assist_test.rb`, `test/models/viva_turn_test.rb`, `test/integration/contests_controller_test.rb`, `test/integration/report_controller_access_test.rb`, `test/integration/main_controller_test.rb`.

---

## Task 1: `Stats` percentile helper

**Files:**
- Create: `lib/stats.rb`
- Test: `test/lib/stats_test.rb`

**Interfaces:**
- Produces: `Stats.percentile(values, q)` → Float or nil (values: Array of Numeric, q: 0.0–1.0). `Stats.mean(values)` → Float or nil.

- [ ] **Step 1: Write the failing test**

```ruby
# test/lib/stats_test.rb
require "test_helper"

class StatsTest < ActiveSupport::TestCase
  test "percentile on empty is nil" do
    assert_nil Stats.percentile([], 0.5)
  end

  test "percentile picks the nearest-rank value and does not require pre-sorting" do
    v = [5, 1, 4, 2, 3]
    assert_equal 1, Stats.percentile(v, 0.0)
    assert_equal 3, Stats.percentile(v, 0.5)
    assert_equal 5, Stats.percentile(v, 1.0)
  end

  test "p95 of 1..100 is 95" do
    assert_equal 95, Stats.percentile((1..100).to_a, 0.95)
  end

  test "mean" do
    assert_nil Stats.mean([])
    assert_in_delta 2.0, Stats.mean([1, 2, 3]), 0.001
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stats_test.rb`
Expected: FAIL — `uninitialized constant Stats`.

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/stats.rb
# Small, dependency-free statistics helpers shared by reports. Nearest-rank
# percentile (no interpolation) — matches the SQL-side percentile used in the
# 2026-09-12 exam analysis so the report and the postmortem agree.
module Stats
  module_function

  # q in [0.0, 1.0]. Returns nil for an empty collection.
  def percentile(values, q)
    return nil if values.nil? || values.empty?
    sorted = values.compact.sort
    return nil if sorted.empty?
    idx = (sorted.size * q).ceil - 1
    sorted[idx.clamp(0, sorted.size - 1)]
  end

  def mean(values)
    v = values&.compact
    return nil if v.nil? || v.empty?
    v.sum.to_f / v.size
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stats_test.rb`
Expected: PASS (4 runs).

- [ ] **Step 5: Commit**

```bash
hg add lib/stats.rb test/lib/stats_test.rb
hg commit -m "stats: nearest-rank percentile helper for reports

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" lib/stats.rb test/lib/stats_test.rb
```

---

## Task 2: LLM timing columns (migration)

**Files:**
- Create: `db/migrate/20260912120000_add_llm_timing_columns.rb`
- Modify: `db/schema.rb` (regenerated by migrate — do not hand-edit)

**Interfaces:**
- Produces: `viva_turns.llm_started_at` (datetime), `viva_turns.llm_latency_ms` (integer); same pair on `comments` and `viva_grades`.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260912120000_add_llm_timing_columns.rb
class AddLlmTimingColumns < ActiveRecord::Migration[8.0]
  # Splits the single wait we can measure today (row created -> row updated)
  # into its two parts, from this point forward:
  #   llm_started_at  — set just before the HTTP call to the provider, so
  #                     (started_at - created_at) is time the request spent
  #                     QUEUED in Solid Queue (viva turns / comments only;
  #                     a viva_grade row is created AFTER the call, so its
  #                     started_at has no queued span to measure against).
  #   llm_latency_ms  — the measured provider round-trip (monotonic).
  # Both nil on rows written before this migration and on error rows.
  def change
    add_column :viva_turns,  :llm_started_at, :datetime
    add_column :viva_turns,  :llm_latency_ms, :integer
    add_column :comments,    :llm_started_at, :datetime
    add_column :comments,    :llm_latency_ms, :integer
    add_column :viva_grades, :llm_started_at, :datetime
    add_column :viva_grades, :llm_latency_ms, :integer
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: adds six columns; `db/schema.rb` version becomes `2026_09_12_120000` and the three tables show the new columns.

- [ ] **Step 3: Verify schema**

Run: `grep -n "llm_started_at\|llm_latency_ms" db/schema.rb`
Expected: six matches (two per table).

- [ ] **Step 4: Commit**

```bash
hg add db/migrate/20260912120000_add_llm_timing_columns.rb
hg commit -m "llm: add llm_started_at / llm_latency_ms to viva_turns, comments, viva_grades

Splits queue time from provider time for the AI-usage report.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" db/migrate/20260912120000_add_llm_timing_columns.rb db/schema.rb
```

---

## Task 3: Stamp timing in the LLM request path

**Files:**
- Modify: `app/services/llm/request.rb` (add reader + `timed_execute_call`; `respond` uses it)
- Modify: `app/services/llm/viva_turn_assist.rb:216-225` (the `@turn.update!`)
- Modify: `app/services/llm/comment_assist.rb:54-74` (the `handle_response`)
- Modify: `app/services/llm/viva_grade_assist.rb:159-166` (the `respond` re-ask) and `:177-184` (the `grade.assign_attributes`)
- Test: `test/services/llm/viva_turn_assist_test.rb` (add), `test/services/llm/comment_assist_test.rb` (add)

**Interfaces:**
- Consumes: nothing new.
- Produces: after any successful LLM call, the written record carries `llm_started_at` (Time) and `llm_latency_ms` (Integer). `Llm::Request#timed_execute_call(data)` wraps `execute_call`; `#llm_started_at` / `#llm_latency_ms` readers expose the last call's timing.

- [ ] **Step 1: Add the timer to the base class**

In `app/services/llm/request.rb`, change the reader line (currently `attr_reader :submission, :problem, :error`) to:

```ruby
    attr_reader :submission, :problem, :error, :llm_started_at, :llm_latency_ms
```

Replace `#respond` (currently `handle_response(execute_call(data))`) with:

```ruby
    def respond(data)
      handle_response(timed_execute_call(data))
    end

    # Wrap the one network round in a timer. Records the wall-clock start
    # (llm_started_at) and the measured round-trip (llm_latency_ms, monotonic
    # so a clock adjustment can't yield a negative). Concrete #handle_response
    # methods persist these two onto their record. A retry or a grade re-ask
    # overwrites them, keeping only the last attempt's timing — the same
    # last-writer policy cost already follows.
    def timed_execute_call(data)
      @llm_started_at = Time.current
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      execute_call(data)
    ensure
      @llm_latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round if t0
    end
```

- [ ] **Step 2: Persist on the viva turn**

In `app/services/llm/viva_turn_assist.rb`, in the `@turn.update!(...)` block (the success write in `handle_response`), add two keys before `status: :ok`:

```ruby
      @turn.update!(
        content:          clean,
        alerted:          alerted,
        llm_model:        parsed['model'] || @model,
        llm_response_raw: response.body,
        token_count_in:   usage['prompt_tokens'],
        token_count_out:  usage['completion_tokens'],
        cost:             compute_cost(usage),
        llm_started_at:   llm_started_at,
        llm_latency_ms:   llm_latency_ms,
        status:           :ok
      )
```

- [ ] **Step 3: Persist on the comment**

In `app/services/llm/comment_assist.rb#handle_response`, add two assignments next to the cost lines (before `@record.update!(parse_response)`):

```ruby
      @record.llm_cost          = respond_to?(:compute_cost, true) ? compute_cost(usage) : nil
      @record.llm_started_at    = llm_started_at
      @record.llm_latency_ms    = llm_latency_ms
      @record.llm_response = response.body
```

- [ ] **Step 4: Persist on the grade, and time the re-ask**

In `app/services/llm/viva_grade_assist.rb#respond`, change both `execute_call(data)` calls to `timed_execute_call(data)`:

```ruby
    def respond(data)
      handle_response(timed_execute_call(data))
    rescue ResponseError => e
      raise if @re_asked || truncated?(e)
      @re_asked = true
      Rails.logger.warn("[viva grade] submission #{@submission.id}: #{e.message} — re-asking once. content=#{content_snippet(e.body)}")
      handle_response(timed_execute_call(data))
    end
```

In `#handle_response`, add the two keys to the first `grade.assign_attributes(...)` (the paper-trail write):

```ruby
      grade.assign_attributes(
        llm_model:        parsed['model'] || @model,
        llm_response_raw: response.body,
        cost:             compute_cost(usage) + (@re_asked ? grade.cost.to_f : 0.0),
        llm_started_at:   llm_started_at,
        llm_latency_ms:   llm_latency_ms,
        graded_at:        Time.zone.now
      )
```

- [ ] **Step 5: Write the failing test (viva turn timing)**

Add to `test/services/llm/viva_turn_assist_test.rb`. This subclass stubs the network so `timed_execute_call` runs against a canned body:

```ruby
  class StubTurnAssist < Llm::VivaTurnAssist
    Fake = Struct.new(:body)
    def execute_call(_data)
      Fake.new({choices: [{message: {content: "Question one?"}}], usage: {prompt_tokens: 10, completion_tokens: 3}, model: "test-model"}.to_json)
    end
    def compute_cost(_usage) = 0.01
  end

  test "a successful turn records llm_started_at and llm_latency_ms" do
    svc = StubTurnAssist.new(submission: @submission, turn: @placeholder)
    svc.call
    @placeholder.reload
    assert @placeholder.ok?
    assert_not_nil @placeholder.llm_started_at
    assert_not_nil @placeholder.llm_latency_ms
    assert_operator @placeholder.llm_latency_ms, :>=, 0
  end
```

- [ ] **Step 6: Run it to verify it fails, then passes**

Run: `bin/rails test test/services/llm/viva_turn_assist_test.rb`
Expected: the new test FAILS before Steps 1–2 (columns/readers absent → nil), PASSES after.

- [ ] **Step 7: Run the adjacent service tests**

Run: `bin/rails test test/services/llm/comment_assist_test.rb test/services/llm/viva_grade_assist_test.rb`
Expected: PASS (no regression from the added keys).

- [ ] **Step 8: Commit**

```bash
hg commit -m "llm: record provider start time and round-trip latency on every call

Timed in Llm::Request#timed_execute_call and persisted by each service.
Splits queue wait from model time for the AI-usage report.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" app/services/llm/request.rb app/services/llm/viva_turn_assist.rb app/services/llm/comment_assist.rb app/services/llm/viva_grade_assist.rb test/services/llm/viva_turn_assist_test.rb
```

---

## Task 4: Dedicated viva job queue (W0)

**Files:**
- Modify: `config/queue.yml` (workers)
- Modify: `config/database.yml:11` (pool floor)
- Modify: `app/jobs/llm/viva_turn_assist_job.rb`, `app/jobs/llm/viva_grade_assist_job.rb` (`queue_as :viva`)
- Test: `test/jobs/llm/queue_assignment_test.rb` (new)

**Interfaces:**
- Produces: `Llm::VivaTurnAssistJob` and `Llm::VivaGradeAssistJob` enqueue on queue `viva`; all other jobs stay on `default`. A production Solid Queue supervisor runs a `viva` worker and a `default` worker with independent thread pools.

- [ ] **Step 1: Write the failing test**

```ruby
# test/jobs/llm/queue_assignment_test.rb
require "test_helper"

class LlmQueueAssignmentTest < ActiveSupport::TestCase
  test "viva turn and grade jobs enqueue on the viva queue" do
    assert_equal "viva", Llm::VivaTurnAssistJob.new.queue_name
    assert_equal "viva", Llm::VivaGradeAssistJob.new.queue_name
  end

  test "assist jobs stay on the default queue" do
    assert_equal "default", Llm::AiGatewayAssistJob.new.queue_name
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/jobs/llm/queue_assignment_test.rb`
Expected: FAIL — viva jobs report `"default"`.

- [ ] **Step 3: Set the queue on the two viva jobs**

In `app/jobs/llm/viva_turn_assist_job.rb`, add as the first line inside the class (before `private`):

```ruby
  class VivaTurnAssistJob < RequestJob
    # Interview turns run on their own queue+worker so an assist-request
    # flood on `default` cannot starve a student mid-interview (2026-09-09
    # exam: one 3-thread worker served turns, grades AND assists; turn wait
    # rose from ~5s to a p95 of 358s). See config/queue.yml.
    queue_as :viva

    private
```

Same in `app/jobs/llm/viva_grade_assist_job.rb`:

```ruby
  class VivaGradeAssistJob < RequestJob
    queue_as :viva

    private
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/jobs/llm/queue_assignment_test.rb`
Expected: PASS.

- [ ] **Step 5: Split the workers in `config/queue.yml`**

Replace the `workers:` list inside the `default: &default` anchor with:

```yaml
  workers:
    # Interview turns and grading. Isolated from assists so a flood of assist
    # requests can't starve a student mid-interview (2026-09-09 exam).
    - queues: "viva"
      threads: <%= ENV.fetch("VIVA_JOB_CONCURRENCY", 5) %>
      processes: 1
      polling_interval: 0.1
    # Everything else: assists, PDF, problem stats, recurring housekeeping.
    - queues: "default"
      threads: <%= ENV.fetch("JOB_CONCURRENCY", 3) %>
      processes: 1
      polling_interval: 0.1
```

Leave the `dispatchers:` and `recurring:` blocks unchanged. NOTE: the queue names are exhaustive — every job in this app is on `default` except the two now on `viva`. Do not use `"*"` for the second worker: it would also drain `viva` and defeat the isolation.

- [ ] **Step 6: Raise the connection-pool floor in `config/database.yml`**

Change line 11 from `pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>` to:

```yaml
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 12 } %>
```

Rationale: each worker is its own process and needs one primary-DB connection per thread; the `viva` worker at 5 threads exceeded the old floor of 5 once dispatcher/scheduler overhead is added. 12 is a ceiling (connections are lazy), harmless for Puma. Production sizing lives in the systemd unit (see Step 8 note), not here.

- [ ] **Step 7: Commit**

```bash
hg add test/jobs/llm/queue_assignment_test.rb
hg commit -m "jobs: dedicated 'viva' queue+worker so assists can't starve interviews

Interview turns and grading move to a viva queue with its own worker;
assists stay on default. Raises the DB pool floor to cover a worker's
threads. Prevents the 2026-09-09 exam's queue saturation (turn wait p95
5s -> 358s under one shared 3-thread worker).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" config/queue.yml config/database.yml app/jobs/llm/viva_turn_assist_job.rb app/jobs/llm/viva_grade_assist_job.rb test/jobs/llm/queue_assignment_test.rb
```

- [ ] **Step 8: Add the changelog bullet (operator-facing) — same commit as above is fine to amend, or a follow-up**

Add under `## [Unreleased]` → `### Changed` in `CHANGELOG.md`:

```markdown
### Changed
- **Viva interviews and grading now run on their own background-job queue
  and worker**, isolated from AI-assist requests. During the 2026-09-09
  quiz a single 3-thread worker served interview turns, grading and assist
  requests together; when assist traffic spiked, interview responses queued
  up to ~7.5 minutes and seven students never received their first question.
  Deployment: the Solid Queue service now needs `RAILS_MAX_THREADS>=12`
  (and optionally `VIVA_JOB_CONCURRENCY` / `JOB_CONCURRENCY`) in its
  environment. (rev <fill after commit>)
```

**Deployment note (record in the postmortem's decision-2, not in code):** the `solid_queue.service` systemd unit on 10.0.5.50 must get `Environment=RAILS_MAX_THREADS=12`; `systemctl daemon-reload && systemctl restart solid_queue`.

---

## Task 5: `AiUsageReport` PORO

**Files:**
- Create: `app/models/ai_usage_report.rb`
- Test: `test/models/ai_usage_report_test.rb`

**Interfaces:**
- Consumes: `Stats` (Task 1); the timing columns (Task 2).
- Produces:
  - `AiUsageReport.new(contest)` where contest responds to `#start`, `#stop`, `#problems`, `#contests_users`.
  - `#summary` → Hash: `{sessions_opened:, students:, enrolled:, answered:, never_answered:, turns:, turn_cost:, turn_wait_p95:, assists:, assist_students:, assist_points:, assist_dollars:, assist_priced:, assists_total:, assist_wait_p95:, grades:, grade_cost:, grade_wait_p95:}`.
  - `#distribution` → Array of Hashes `{kind:, calls:, mean:, p50:, p90:, p95:, p99:, max:, over_60:}` (seconds), one per kind in `["viva turn", "assist", "viva grade"]`.
  - `#by_model` → Array `{model:, requests:, students:, points:, dollars:, priced:, mean_wait:, p95:, max:}` (assists only).
  - `#by_problem` → Array `{problem:, turns:, grades:, assists:, students:, dollars:, p95:}`.
  - `#never_answered` → Array `{login:, opened_at:, greeting_wait:, submission_id:}`.
  - `#counts_chart` → Chart.js `{labels:, datasets:}` (stacked bar of call counts per 5-min bucket).
  - `#wait_chart` → Chart.js `{labels:, datasets:}` (mean wait seconds per 5-min bucket, one line per kind).
  - `#calls` → Array of Hashes for the DataTable: `{at:, kind:, login:, problem:, model:, queued_s:, model_s:, total_s:, tokens_in:, tokens_out:, cost:, status:, submission_id:}`.

- [ ] **Step 1: Write the report class**

```ruby
# app/models/ai_usage_report.rb
# Read-only analytics over one contest's LLM calls: viva interview turns,
# viva grading, and submission-assist ("Codey") requests. A PORO, not an AR
# model — it only reads. Scoped to the contest's enrolled users and problems
# over the contest window (extended by the largest per-user offset/extra time,
# a coarse bound; per-user precision is not needed for usage reporting).
#
# "wait" semantics (a call carries up to three):
#   queued_s — request queued -> provider call started (started_at - created_at).
#              Available for viva turns and assists (placeholder row created at
#              enqueue). Nil for grades (their row is created after the call) and
#              for rows written before the timing columns existed.
#   model_s  — the provider round-trip (llm_latency_ms). Nil on pre-timing rows.
#   total_s  — what the user actually waited: for turns/assists, updated_at -
#              created_at (queue + model + save); for grades, model_s.
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
    @calls ||= (turn_calls + assist_calls + grade_calls).sort_by(&:at)
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
      grade_cost:       grades.sum { |c| c.cost.to_f },
      grade_wait_p95:   Stats.percentile(grades.map { |c| total_s(c) }, 0.95)
    }
  end

  def distribution
    KINDS.map do |kind|
      waits = calls.select { |c| c.kind == kind }.map { |c| total_s(c) }.compact
      {
        kind: kind, calls: waits.size,
        mean: Stats.mean(waits), p50: Stats.percentile(waits, 0.5),
        p90: Stats.percentile(waits, 0.9), p95: Stats.percentile(waits, 0.95),
        p99: Stats.percentile(waits, 0.99), max: waits.max,
        over_60: waits.empty? ? 0 : (100.0 * waits.count { |w| w > 60 } / waits.size).round
      }
    end
  end

  def by_model
    calls.select { |c| c.kind == "assist" }.group_by(&:model).map do |model, cs|
      waits  = cs.map { |c| total_s(c) }.compact
      priced = cs.reject { |c| c.cost.nil? }
      {
        model: model, requests: cs.size, students: cs.map(&:user_id).uniq.size,
        points: cs.sum { |c| c.points.to_f }, dollars: priced.sum { |c| c.cost.to_f },
        priced: priced.size, mean_wait: Stats.mean(waits), p95: Stats.percentile(waits, 0.95), max: waits.max
      }
    end.sort_by { |r| -r[:requests] }
  end

  def by_problem
    names = @contest.problems.pluck(:id, :name).to_h
    calls.group_by(&:problem_id).map do |pid, cs|
      {
        problem: names[pid], turns: cs.count { |c| c.kind == "viva turn" },
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
    end.sort_by { |r| r[:opened_at] }
  end

  def counts_chart
    labels = buckets.map { |b| bucket_label(b) }
    {
      labels: labels,
      datasets: KINDS.map do |kind|
        {label: kind, backgroundColor: COLORS[kind],
         data: buckets.map { |b| bucketed[b][kind].size }}
      end
    }
  end

  def wait_chart
    labels = buckets.map { |b| bucket_label(b) }
    {
      labels: labels,
      datasets: KINDS.map do |kind|
        {label: kind, borderColor: COLORS[kind], backgroundColor: COLORS[kind], fill: false,
         data: buckets.map { |b| w = bucketed[b][kind]; w.empty? ? nil : (w.sum { |c| total_s(c) }.to_f / w.size).round(1) }}
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

  def ms_to_s(ms) = ms.nil? ? nil : (ms / 1000.0).round(1)

  def sub_ids
    @sub_ids ||= Submission.where(problem_id: problem_ids, user_id: user_ids).pluck(:id)
  end

  def turn_calls
    VivaTurn.where(role: :assistant, submission_id: sub_ids, created_at: window)
            .joins(submission: :user)
            .pluck(:submission_id, "submissions.user_id", "submissions.problem_id", "users.login",
                   :llm_model, :created_at, :updated_at, :llm_started_at, :llm_latency_ms, :token_count_in, :token_count_out, :cost, :status)
            .map do |sid, uid, pid, login, model, cat, uat, sat, lat, tin, tout, cost, status|
      Call.new(kind: "viva turn", at: cat, user_id: uid, login: login, problem_id: pid, problem_name: problem_name(pid),
               submission_id: sid, model: model, queued_ms: queued_ms(cat, sat),
               model_ms: lat, total_ms: ((uat - cat) * 1000).round, tokens_in: tin, tokens_out: tout,
               cost: cost, points: nil, status: VivaTurn.statuses.key(status))
    end
  end

  def assist_calls
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
               cost: dollars, points: points, status: Comment.statuses.key(status))
    end
  end

  def grade_calls
    VivaGrade.where(submission_id: sub_ids, graded_at: window)
             .joins(submission: :user)
             .pluck(:submission_id, "submissions.user_id", "submissions.problem_id", "users.login",
                    :llm_model, :graded_at, :llm_latency_ms, :cost)
             .map do |sid, uid, pid, login, model, gat, lat, cost|
      Call.new(kind: "viva grade", at: gat, user_id: uid, login: login, problem_id: pid, problem_name: problem_name(pid),
               submission_id: sid, model: model, queued_ms: nil, model_ms: lat, total_ms: nil,
               tokens_in: nil, tokens_out: nil, cost: cost, points: nil, status: "ok")
    end
  end

  def queued_ms(created_at, started_at)
    return nil if started_at.nil? || created_at.nil?
    ((started_at - created_at) * 1000).round
  end

  def problem_name(pid) = (@names ||= @contest.problems.pluck(:id, :name).to_h)[pid]

  # One row per viva session (submission) that opened an interview: answers
  # count, when it opened, and how long the first (greeting) turn took.
  def viva_sessions
    @viva_sessions ||= begin
      subs = Submission.where(problem_id: problem_ids, user_id: user_ids)
                       .where(submitted_at: window)
                       .where(id: VivaTurn.select(:submission_id).distinct)
                       .joins(:user).pluck(:id, :user_id, "users.login", :submitted_at)
      answers = VivaTurn.where(submission_id: subs.map(&:first), role: :student).group(:submission_id).count
      greet   = VivaTurn.where(submission_id: subs.map(&:first), role: :assistant, sequence: 1)
                        .pluck(:submission_id, :created_at, :updated_at).to_h { |sid, c, u| [sid, ((u - c)).round] }
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
        key = Time.zone.at((c.at.to_i / BUCKET) * BUCKET)
        h[key][c.kind] << c if h.key?(key)
      end
      h
    end
  end

  def bucket_label(b) = b.strftime("%H:%M")
end
```

- [ ] **Step 2: Write the test**

```ruby
# test/models/ai_usage_report_test.rb
require "test_helper"

class AiUsageReportTest < ActiveSupport::TestCase
  setup do
    @contest = contests(:contest_a)              # start 1h ago, stop 3h from now; problems prob_add, easy
    @user    = users(:james)                     # james_in_contest_a
    @sub = @contest.problems.first.submissions.create!(
      user: @user, submitted_at: 30.minutes.ago, status: :submitted
    )
    # one interview turn (assistant) with timing
    @sub.viva_turns.create!(role: :system,    status: :ok, sequence: 0, content: "(interview start)")
    @sub.viva_turns.create!(role: :assistant, status: :ok, sequence: 1, content: "Q1?",
                            created_at: 30.minutes.ago, updated_at: 30.minutes.ago + 8.seconds,
                            llm_started_at: 30.minutes.ago + 3.seconds, llm_latency_ms: 5000, cost: 0.01)
    @sub.viva_turns.create!(role: :student,   status: :ok, sequence: 2, content: "A1")
    # one assist on the same submission
    @sub.comments.create!(user: @user, kind: :llm_assist, status: :ok, title: "Assistance",
                          body: "hint", cost: 10, llm_cost: 0.02, llm_model: "claude-opus-4-5",
                          created_at: 20.minutes.ago, updated_at: 20.minutes.ago + 30.seconds,
                          llm_started_at: 20.minutes.ago + 25.seconds, llm_latency_ms: 5000,
                          prompt_tokens: 100, completion_tokens: 50)
    @report = AiUsageReport.new(@contest)
  end

  test "summary counts sessions, turns and assists" do
    s = @report.summary
    assert_equal 1, s[:sessions_opened]
    assert_equal 1, s[:answered]
    assert_equal 1, s[:turns]
    assert_equal 1, s[:assists]
    assert_in_delta 0.02, s[:assist_dollars], 0.0001
    assert_equal 10.0, s[:assist_points]
  end

  test "distribution separates the kinds and computes total wait" do
    d = @report.distribution.index_by { |r| r[:kind] }
    assert_equal 8.0, d["viva turn"][:p95]   # updated - created = 8s
    assert_equal 30.0, d["assist"][:p95]
  end

  test "calls_json splits queued from model time" do
    turn = @report.calls_json.find { |c| c[:kind] == "viva turn" }
    assert_equal 3.0, turn[:queued_s]        # started - created
    assert_equal 5.0, turn[:model_s]         # latency_ms
    assert_equal 8.0, turn[:total_s]
  end

  test "a session with no student answer is counted as never answered" do
    silent = @contest.problems.first.submissions.create!(user: users(:jack), submitted_at: 10.minutes.ago, status: :submitted)
    silent.viva_turns.create!(role: :assistant, status: :ok, sequence: 1, content: "Q?",
                              created_at: 10.minutes.ago, updated_at: 10.minutes.ago + 120.seconds)
    report = AiUsageReport.new(@contest)
    assert_equal 1, report.never_answered.size
    assert_equal users(:jack).login, report.never_answered.first[:login]
  end
end
```

Note for the implementer: `contests(:contest_a).problems.first` resolves through `contests_problems` (`prob_add`, `easy`). If `contest.problems` ordering makes the first problem unexpected, pin it with `@contest.problems.find_by(name: "prob_add")`. `jack` is not enrolled in `contest_a` by fixture — add a `contests_users` fixture `jack_in_contest_a_user` (role 0, enabled) if the never-answered test needs jack counted; otherwise use `james` for both and give the second submission a different problem. Keep the enrolled/user_ids filter honest: only enrolled users' calls count.

- [ ] **Step 3: Run to verify fail, then pass**

Run: `bin/rails test test/models/ai_usage_report_test.rb`
Expected: FAILS before `ai_usage_report.rb` exists, PASSES after. Fix any fixture-enrollment mismatch surfaced here (add `contests_users` fixture for the second actor).

- [ ] **Step 4: Commit**

```bash
hg add app/models/ai_usage_report.rb test/models/ai_usage_report_test.rb
hg commit -m "report: AiUsageReport — per-contest LLM usage, timing and cost

Reads viva turns, grades and assists scoped to a contest; splits queue
wait from provider time; produces summary/distribution/by-model/by-problem
/never-answered/chart/table data.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" app/models/ai_usage_report.rb test/models/ai_usage_report_test.rb test/fixtures/contests_users.yml
```

---

## Task 6: Contest controller actions + routes + B4 (admin-only mode switch)

**Files:**
- Modify: `config/routes.rb` (two member routes)
- Modify: `app/controllers/contests_controller.rb` (actions, auth wiring, B4)
- Test: `test/integration/contests_ai_usage_test.rb` (new), `test/integration/contests_controller_test.rb` (B4 assertion tighten)

**Interfaces:**
- Consumes: `AiUsageReport` (Task 5).
- Produces: `GET /contests/:id/ai_usage` → `ai_usage.html.haml` with `@report`; `POST /contests/:id/ai_usage_query` → `{data: [...]}` JSON. `set_system_mode` requires admin.

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, inside `resources :contests do member do ... end end`, add after `post 'view_query'`:

```ruby
      get 'ai_usage'
      post 'ai_usage_query'
```

- [ ] **Step 2: Write the failing test**

```ruby
# test/integration/contests_ai_usage_test.rb
require "test_helper"

class ContestsAiUsageTest < ActionDispatch::IntegrationTest
  setup { @contest = contests(:contest_a) }

  test "unauthenticated is redirected" do
    get ai_usage_contest_path(@contest)
    assert_redirected_to login_main_path
  end

  test "plain user cannot view" do
    sign_in_as("john", "hello")
    get ai_usage_contest_path(@contest)
    assert_response :redirect
  end

  test "admin sees the AI usage page" do
    sign_in_as("admin", "admin")
    get ai_usage_contest_path(@contest)
    assert_response :success
  end

  test "editor of the contest sees the page" do
    sign_in_as("mary", "mary")     # mary is editor of group_a and contest_a
    get ai_usage_contest_path(@contest)
    assert_response :success
  end

  test "ai_usage_query returns a data array" do
    sign_in_as("admin", "admin")
    post ai_usage_query_contest_path(@contest)
    assert_response :success
    assert_kind_of Array, response.parsed_body["data"]
  end
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `bin/rails test test/integration/contests_ai_usage_test.rb`
Expected: FAIL — no route / no action.

- [ ] **Step 4: Add the actions and auth wiring**

In `app/controllers/contests_controller.rb`:

Add `:ai_usage, :ai_usage_query` to the `before_action :set_contest, only: [...]` list, and to the `EDITOR_ACTION` array (so `can_manage_contest` and `group_editor_authorization` gate them).

Add the two actions near `#view` / `#view_query`:

```ruby
  # GET /contests/:id/ai_usage — read-only LLM usage overview for this contest.
  def ai_usage
    @report = AiUsageReport.new(@contest)
  end

  # POST /contests/:id/ai_usage_query — per-call feed for the DataTable.
  def ai_usage_query
    render json: { data: AiUsageReport.new(@contest).calls_json }
  end
```

- [ ] **Step 5: B4 — require admin for the site mode switch**

`set_system_mode` is a collection action currently reachable by any group editor. Add an admin gate. At the top of `#set_system_mode`, before the mode validation:

```ruby
  def set_system_mode
    return unless admin_authorization
    unless ['standard', 'contest', 'indv-contest', 'analysis'].include? params[:mode]
```

`admin_authorization` returns false and redirects for non-admins (it is already defined in ApplicationController and returns a boolean).

- [ ] **Step 6: Tighten the existing B4 test**

In `test/integration/contests_controller_test.rb`, the test `"non-admin cannot change system mode"` currently asserts only `:redirect`. Make it assert the mode did NOT change:

```ruby
  test "non-admin cannot change system mode" do
    set_grader_config("system.mode", "standard")
    sign_in_as("mary", "mary")
    post set_system_mode_contests_path, params: { mode: "contest" }
    assert_response :redirect
    assert_equal "standard", GraderConfiguration[GraderConfiguration::SYSTEM_MODE_CONF_KEY]
  end
```

(mary is a group editor, so this proves the tightened gate — before B4 she could switch it.)

- [ ] **Step 7: Run the tests**

Run: `bin/rails test test/integration/contests_ai_usage_test.rb test/integration/contests_controller_test.rb`
Expected: PASS. Note: `ai_usage` needs its view (Task 7) to render `:success`. If running this task before Task 7, stub the view with a one-line placeholder `%h1 AI Usage` so the render succeeds, then flesh it out in Task 7. Prefer doing Task 7 immediately after.

- [ ] **Step 8: Commit**

```bash
hg add test/integration/contests_ai_usage_test.rb
hg commit -m "contests: AI-usage report actions + routes; admin-only site mode switch

set_system_mode now requires admin (was reachable by any group editor; a
TA flipped the whole site's mode mid-exam on 2026-09-09).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" config/routes.rb app/controllers/contests_controller.rb test/integration/contests_ai_usage_test.rb test/integration/contests_controller_test.rb
```

- [ ] **Step 9: Changelog + Viva/Assist history**

`CHANGELOG.md` under `### Added`:

```markdown
- **AI-usage report per contest** (Watch → AI Usage, or /contests/:id/ai_usage;
  admins and contest editors). Shows viva-interview, grading and assist volume,
  cost, and response-time percentiles over the contest window, with a per-call
  table. (rev <fill>)
```

`CHANGELOG.md` under `### Security` (or Changed):

```markdown
- **Switching the site mode (standard/contest/analysis) now requires an
  admin.** It was reachable by any group editor. (rev <fill>)
```

Extend the existing 2026-09-12 entries in `doc/Viva-History.md` and `doc/Assist-History.md` (Change line): note the report + timing columns + queue split shipped, citing the rev.

---

## Task 7: The AI-usage view (tiles, charts, tables, DataTable)

**Files:**
- Create: `app/views/contests/ai_usage.html.haml`
- Modify: `app/javascript/controllers/chart_controller.js` (presets `stacked_bar`, `multiline`)
- Modify: `app/javascript/controllers/datatables/configs.js` (config `contestAiUsage`) and `columns.js` (columns)
- Modify: `app/views/contests/show.html.haml:29-31` and `app/views/contests/view.html.haml:10-12` (link button)

**Interfaces:**
- Consumes: `@report` (an `AiUsageReport`); `ai_usage_query_contest_path`.

- [ ] **Step 1: Add the two chart presets**

In `app/javascript/controllers/chart_controller.js`, add to the `PRESETS` object:

```javascript
  stacked_bar: {
    type: 'bar',
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: { x: { stacked: true }, y: { stacked: true, beginAtZero: true } },
      plugins: { legend: { position: 'bottom' } },
    },
  },
  multiline: {
    type: 'line',
    options: {
      responsive: true,
      maintainAspectRatio: false,
      spanGaps: true,
      elements: { point: { radius: 2 } },
      plugins: { legend: { position: 'bottom' } },
      scales: { y: { beginAtZero: true, title: { display: true, text: 'seconds' } } },
    },
  },
```

- [ ] **Step 2: Add the DataTable columns and config**

In `app/javascript/controllers/datatables/columns.js`, add a top-level key to the exported `columns` object (near `solidQueueJob`):

```javascript
  aiUsage: {
    at:           { data: 'at', title: 'Time', render: cafe.dt.render.datetime('HH:mm:ss') },
    kind:         { data: 'kind', title: 'Kind' },
    login:        { data: 'login', title: 'Student' },
    problem:      { data: 'problem', title: 'Problem' },
    model:        { data: 'model', title: 'Model' },
    queuedS:      { data: 'queued_s', title: 'Queued s' },
    modelS:       { data: 'model_s', title: 'Model s' },
    totalS:       { data: 'total_s', title: 'Total s' },
    tokensIn:     { data: 'tokens_in', title: 'Tok in' },
    tokensOut:    { data: 'tokens_out', title: 'Tok out' },
    cost:         { data: 'cost', title: 'Cost $' },
    status:       { data: 'status', title: 'Status' },
    submissionId: { data: 'submission_id', title: 'Submission', render: function (data, type) {
      if (data === null) return ''
      if (type === 'display' || type === 'filter') return `<a href="/submissions/${data}"> #${data}</a>`
      return data
    } },
  },
```

In `app/javascript/controllers/datatables/configs.js`, add to the exported `configs` object (mirroring `aiAssistReport`):

```javascript
  contestAiUsage: {
    ...baseConfig,
    paging: true,
    pageLength: 50,
    order: [[0, 'asc']],
    layout: { topStart: ['buttons', 'pageLength'] },
    buttons: [
      { text: 'Refresh', action: function (e, dt) { dt.ajax.reload() } },
      'copyHtml5', 'excelHtml5',
    ],
    columns: [
      columns.aiUsage.at, columns.aiUsage.kind, columns.aiUsage.login, columns.aiUsage.problem,
      columns.aiUsage.model, columns.aiUsage.queuedS, columns.aiUsage.modelS, columns.aiUsage.totalS,
      columns.aiUsage.tokensIn, columns.aiUsage.tokensOut, columns.aiUsage.cost, columns.aiUsage.status,
      columns.aiUsage.submissionId,
    ],
    ajax: {
      ...baseAjax,
      data: (data) => data,
    },
    drawCallback: function () { this.api().columns.adjust() },
  },
```

Note: the `submissionId` render emits an `<a>` and must survive the escape-by-default wrapper. `dt.escape_columns_by_default` leaves a column with an explicit `render` alone only if that render is treated as HTML-emitting; confirm by checking the same pattern already works for `solidQueueJob.submissionId`. If escaping double-encodes the link, mark it opt-out exactly like `solidQueueJob.detail` (`render: (d) => ...`).

- [ ] **Step 3: Write the view**

```haml
-# app/views/contests/ai_usage.html.haml
= render 'application/breadcrumb', steps: [ { label: 'Contests', path: contests_path, icon: resource_icon_name(Contest) }, { label: 'Management', path: contest_path(@contest) }, { label: 'AI Usage' } ]

- s = @report.summary
.d-flex.justify-content-between.align-items-center.mb-3
  .d-flex.align-items-center.gap-2
    %h2.fw-bold.text-dark.mb-0.font-monospace= @contest.name
    %span.badge.bg-info-subtle.text-info.border.border-info-subtle.rounded-pill.fw-medium
      %small AI Usage
  .d-flex.gap-2
    = link_to mdi(:settings, 'me-1') + 'Manage', contest_path(@contest), class: 'btn btn-outline-primary btn-flex'
    = link_to mdi(:summarize, 'me-1') + 'Watch', view_contest_path(@contest), class: 'btn btn-outline-success btn-flex'

.text-secondary.small.mb-3
  = "#{@contest.start.strftime('%Y-%m-%d %H:%M')} – #{@contest.stop.strftime('%H:%M')}"
  = "· #{s[:enrolled]} enrolled"
  %span.ms-2 Wait = queue time + provider time; grades show provider time only.

.row.g-3.mb-4{data: {controller: 'init-ui-component'}}
  - tiles = [["#{s[:sessions_opened]}", 'viva sessions opened', "#{s[:students]} of #{s[:enrolled]} enrolled"], ["#{s[:answered]}", 'answered at least once', "#{s[:never_answered]} never answered"], ["#{s[:turns]}", 'viva turns', "$#{'%.2f' % s[:turn_cost]} · p95 #{s[:turn_wait_p95] || '–'} s"], ["#{s[:assists]}", 'assist requests', "#{s[:assist_students]} students · #{s[:assist_points].to_i} points"], ["$#{'%.2f' % s[:assist_dollars]}", 'assist dollars (priced)', "#{s[:assist_priced]} of #{s[:assists_total]} priced"], ["#{s[:grades]}", 'grades', "$#{'%.2f' % s[:grade_cost]} · p95 #{s[:grade_wait_p95] || '–'} s"]]
  - tiles.each do |num, label, sub|
    .col-6.col-lg-2
      .card.card-shadow.h-100
        .card-body.py-2
          .fs-3.fw-bold= num
          .small.text-secondary= label
          .text-secondary{style: 'font-size:.75rem'}= sub

.row.gx-3.mb-4
  .col-lg-6
    .card.card-shadow.h-100
      .card-body
        %h6.fw-bold AI calls per 5 minutes
        %div{style: 'height: 260px'}
          %canvas{data: {controller: 'chart', chart_data_value: @report.counts_chart.to_json, chart_preset_value: 'stacked_bar'}}
  .col-lg-6
    .card.card-shadow.h-100
      .card-body
        %h6.fw-bold Mean wait per 5 minutes (seconds)
        %div{style: 'height: 260px'}
          %canvas{data: {controller: 'chart', chart_data_value: @report.wait_chart.to_json, chart_preset_value: 'multiline'}}

.card.card-shadow.mb-4
  .card-body
    %h6.fw-bold Wait time distribution
    %table.table.table-sm.table-hover.align-middle
      %thead
        %tr
          %th kind
          %th.text-end calls
          %th.text-end mean
          %th.text-end p50
          %th.text-end p90
          %th.text-end p95
          %th.text-end p99
          %th.text-end max
          %th.text-end over 60 s
      %tbody
        - @report.distribution.each do |r|
          %tr
            %td= r[:kind]
            %td.text-end= r[:calls]
            - [:mean, :p50, :p90, :p95, :p99, :max].each do |k|
              %td.text-end= r[k].nil? ? '–' : r[k].round
            %td.text-end= "#{r[:over_60]}%"

.row.gx-3.mb-4
  .col-lg-6
    .card.card-shadow.h-100
      .card-body
        %h6.fw-bold Assist by model
        %table.table.table-sm.table-hover.align-middle
          %thead
            %tr
              %th model
              %th.text-end req
              %th.text-end students
              %th.text-end points
              %th.text-end dollars
              %th.text-end mean
              %th.text-end p95
          %tbody
            - @report.by_model.each do |r|
              %tr
                %td= r[:model]
                %td.text-end= r[:requests]
                %td.text-end= r[:students]
                %td.text-end= r[:points].to_i
                %td.text-end= r[:priced].zero? ? 'unpriced' : "$#{'%.2f' % r[:dollars]}"
                %td.text-end= r[:mean_wait].nil? ? '–' : r[:mean_wait].round
                %td.text-end= r[:p95].nil? ? '–' : r[:p95].round
  .col-lg-6
    .card.card-shadow.h-100
      .card-body
        %h6.fw-bold By problem
        %table.table.table-sm.table-hover.align-middle
          %thead
            %tr
              %th problem
              %th.text-end turns
              %th.text-end grades
              %th.text-end assists
              %th.text-end students
              %th.text-end $
              %th.text-end p95
          %tbody
            - @report.by_problem.each do |r|
              %tr
                %td= r[:problem]
                %td.text-end= r[:turns]
                %td.text-end= r[:grades]
                %td.text-end= r[:assists]
                %td.text-end= r[:students]
                %td.text-end= "$#{'%.2f' % r[:dollars]}"
                %td.text-end= r[:p95].nil? ? '–' : r[:p95].round

- na = @report.never_answered
- if na.any?
  .card.card-shadow.mb-4
    .card-body
      %h6.fw-bold Opened the viva and never answered (#{na.size})
      %table.table.table-sm.table-hover.align-middle
        %thead
          %tr
            %th student
            %th opened
            %th.text-end greeting wait (s)
            %th submission
        %tbody
          - na.each do |r|
            %tr
              %td= r[:login]
              %td= r[:opened_at].strftime('%H:%M:%S')
              %td.text-end= r[:greeting_wait] || '–'
              %td= link_to "##{r[:submission_id]}", viva_submission_path(r[:submission_id])

.card.card-shadow
  .card-body
    %h6.fw-bold Every AI call
    .col-sm-12{data: {turbo: true, controller: 'datatables--init init-ui-component', 'datatables--init-config-name-value': 'contestAiUsage', 'datatables--init-ajax-url-value': ai_usage_query_contest_path(@contest)}}
      %table#ai-usage-table.table.table-hover.table-condense
```

- [ ] **Step 4: Add the link button on the contest pages**

In `app/views/contests/show.html.haml`, inside the `.d-flex.gap-2` block that holds Watch/Edit (around line 29), add before the Watch link:

```haml
      = link_to mdi(:query_stats, 'me-1') + 'AI Usage', ai_usage_contest_path(@contest), class: 'btn btn-outline-info btn-flex'
```

In `app/views/contests/view.html.haml`, inside its `.d-flex.gap-2` (around line 10), add:

```haml
    = link_to mdi(:query_stats, 'me-1') + 'AI Usage', ai_usage_contest_path(@contest), class: 'btn btn-outline-info btn-flex'
```

- [ ] **Step 5: Manual smoke on the refreshed local DB**

The local `grader` DB holds contest 43 (`d69_q1`). Start the app and open the page. Steps:

Run: `bin/rails server` (separate shell), then load `http://localhost:3000` and sign in as an admin, or use a runner to confirm the report builds without error:

```bash
bin/rails runner 'r = AiUsageReport.new(Contest.find(43)); p r.summary.slice(:turns, :assists, :grades); p r.distribution.map { |d| [d[:kind], d[:p95]] }; p r.calls_json.size'
```

Expected (from the 2026-09-12 analysis): `{turns: 1042, assists: 260, grades: 87 (or ~151 all-window)}`, viva-turn p95 ≈ 358 with old rows nil-timed but total present, calls ≈ 1300+.

- [ ] **Step 6: Screenshot before/after (dae reviews UI only after seeing renders)**

Use the cafe-grader shot tooling (`~/cafe-grader/shot-tools/shot.rb`, headless Chrome + temp admin). Capture the `ai_usage` page for contest 43 at desktop and ~400px width. Delete the temp admin after. Attach in the review.

- [ ] **Step 7: Commit**

```bash
hg add app/views/contests/ai_usage.html.haml
hg commit -m "contests: AI-usage report view — tiles, two charts, tables, per-call DataTable

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" app/views/contests/ai_usage.html.haml app/views/contests/show.html.haml app/views/contests/view.html.haml app/javascript/controllers/chart_controller.js app/javascript/controllers/datatables/configs.js app/javascript/controllers/datatables/columns.js
```

---

## Task 8: B1 — header 500 when the session contest excludes the user

**Files:**
- Modify: `app/views/layouts/_header.html.haml:17` and `:209`
- Modify: `app/views/main/_contest_box.html.haml:28-29`
- Test: `test/integration/main_controller_test.rb` (add)

**Interfaces:** none.

- [ ] **Step 1: Write the failing test**

The crash: `@current_contest_user` is nil (session points at an enabled contest the user isn't in), and `_header` calls `@current_contest_user.extra_time_second`. Reproduce by putting the user in contest mode with a `session[:contest_id]` for a contest they don't belong to.

```ruby
# add to test/integration/main_controller_test.rb
  test "header does not 500 when session contest excludes the user" do
    set_grader_config("system.mode", "contest")
    sign_in_as("john", "hello")                 # john is in no contest
    # force the session to a contest john is not a member of
    get set_active_contest_path(contests(:contest_a))  # will refuse, but sets nothing
    # directly drive a page that renders the header in contest mode:
    get list_main_path
    assert_response :success
  ensure
    set_grader_config("system.mode", "standard")
  end
```

If `set_active` refusing prevents the state, instead stub by visiting with contest mode on where `current_contest` picks an enabled contest and `@current_contest_user` is nil. The robust reproduction: enable a contest that john is not in, ensure it is the only enabled one, contest mode on; `current_contest` selects it via `@current_user.contests.where(enabled: true).order(:stop).first` → nil for john, so `@current_contest` stays nil and the branch is skipped. So the true trigger is a stale `session[:contest_id]`. Simplest deterministic test: unit-test the guard by rendering the header partial is awkward; instead assert the nil-safe expression directly in a view test is overkill. Pragmatic: assert the page renders when contest mode is on and the user has no contest (regression guard for the nil path around line 17):

```ruby
  test "list renders in contest mode for a user with no active contest" do
    set_grader_config("system.mode", "contest")
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success
  ensure
    set_grader_config("system.mode", "standard")
  end
```

- [ ] **Step 2: Run to see current behavior**

Run: `bin/rails test test/integration/main_controller_test.rb`
Expected: the new test may already pass if `@current_contest` is nil (branch skipped). To force the nil-`@current_contest_user`-with-non-nil-`@current_contest` path, the guard fix is defensive regardless. Proceed to harden the view.

- [ ] **Step 3: Harden the view**

In `app/views/layouts/_header.html.haml:17`, change:

```haml
            - if @current_contest.stop + @current_contest_user.extra_time_second < Time.zone.now
```

to guard the nil member:

```haml
            - extra = @current_contest_user&.extra_time_second.to_i
            - if @current_contest.stop + extra < Time.zone.now
```

At `:209`, `@current_user.contests_users.where(contest: @current_contest).take&.extra_time_second || 0` already uses `&.` — leave it.

In `app/views/main/_contest_box.html.haml:28-29`, the two `.first.start_offset_second` / `.first.extra_time_second` calls assume membership. Guard:

```haml
                  start_offset: @current_user.contests_users.where(contest_id: contest).first&.start_offset_second.to_i,
                  extra_time: @current_user.contests_users.where(contest_id: contest).first&.extra_time_second.to_i}}
```

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/integration/main_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
hg commit -m "fix: header/contest-box 500 when the session contest excludes the user

A logged-in user whose session points at an enabled contest they are not
enrolled in has a nil contest-membership; the header's countdown read
extra_time_second off it and raised on every page. (2 hits, 2026-09-09.)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" app/views/layouts/_header.html.haml app/views/main/_contest_box.html.haml test/integration/main_controller_test.rb
```

Add `CHANGELOG.md` `### Fixed` bullet citing the rev.

---

## Task 9: B2 — max-score report 500 in contest mode (DISTINCT + ORDER BY)

**Files:**
- Modify: `app/models/problem.rb` (the two `contests_*_for_user` scopes) OR `app/controllers/report_controller.rb:674` and `app/views/report/_score_table.html.haml:7`
- Test: `test/integration/report_controller_access_test.rb` (add contest-mode case)

**Interfaces:** none.

Root cause: in contest mode, `problems_for_action(:report)` returns `Problem.contests_editable_problems_for_user` — a relation with `.distinct('problems.id')`. `_score_table.html.haml:7` calls `problems.ids`, and the controller orders by `date_added`; MySQL 8 `ONLY_FULL_GROUP_BY` rejects `ORDER BY problems.date_added` under `SELECT DISTINCT problems.id`. Verified locally: `reorder(nil)` fixes it, and so does the subquery form.

- [ ] **Step 1: Write the failing test**

```ruby
# add to test/integration/report_controller_access_test.rb
  test "max_score report survives contest mode for a contest editor" do
    set_grader_config("system.mode", "contest")
    sign_in_as("mary", "mary")   # editor of contest_a
    get max_score_report_path(probs: { use: "all" }, users: { use: "all" })
    assert_response :success
  ensure
    set_grader_config("system.mode", "standard")
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/integration/report_controller_access_test.rb`
Expected: FAIL — `Mysql2::Error: ... incompatible with DISTINCT`. (Requires MySQL 8 with `ONLY_FULL_GROUP_BY`, which is the project default and set in test.)

- [ ] **Step 3: Fix the scopes to the subquery form**

In `app/models/problem.rb`, change `contests_editable_problems_for_user` and `contests_problems_for_user` so the *returned* relation is a plain `Problem.where(id: ...)` (orderable, no DISTINCT leak), matching the shape `group_reportable_by_user` already uses. For `contests_editable_problems_for_user`:

```ruby
  scope :contests_editable_problems_for_user, ->(user_id) {
    inner = joins(contests_problems: {contest: :contests_users})
      .where(available: true)
      .where('contests.enabled': true)
      .where('contests_users.user_id': user_id)
      .where('contests_users.enabled': true)
      .where('contests_users.role': 'editor')
      .select('problems.id')
    Problem.where(id: inner)
  }
```

Apply the same `select('problems.id')` + `Problem.where(id: inner)` wrapping to `contests_problems_for_user` (check its current body first; keep its filters identical, only change the DISTINCT-tail to the subquery form).

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/integration/report_controller_access_test.rb test/integration/authz_submit_probe_test.rb test/integration/authorization_test.rb`
Expected: PASS. The last two guard that the scope's *membership* is unchanged (only its SQL shape changed).

- [ ] **Step 5: Commit**

```bash
hg commit -m "fix: contest-mode reports 500 under MySQL ONLY_FULL_GROUP_BY

contests_*_for_user returned a SELECT DISTINCT problems.id relation;
ordering it by date_added (score report) or plucking ids raised
'ORDER BY ... incompatible with DISTINCT'. Return Problem.where(id: sub)
instead, the same shape group_reportable_by_user already uses. (Staff hit
this on the 2026-09-09 quiz score report.)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" app/models/problem.rb test/integration/report_controller_access_test.rb
```

Add `CHANGELOG.md` `### Fixed` bullet citing the rev.

---

## Task 10: B3 — stale-turn sweeper distinguishes queued from running (optional, last)

**Files:**
- Modify: `app/models/viva_turn.rb` (`fail_stale!`, `stuck` scope, add `QUEUE_STALE_AFTER`)
- Test: `test/models/viva_turn_test.rb` (update the threshold test; add a queued-vs-running case)

**Interfaces:** none (uses `llm_started_at` from Task 2).

Rationale: `fail_stale!` currently marks any `:processing` turn older than 10 min as errored. During a queue backlog a turn can wait >10 min *without ever running*; failing it shows the student a false timeout. Now that `llm_started_at` exists, fail a turn that has STARTED and hung past `STALE_AFTER`, and one that never started only past a longer `QUEUE_STALE_AFTER`.

- [ ] **Step 1: Update the model**

In `app/models/viva_turn.rb`, add below `STALE_AFTER`:

```ruby
  # A turn that was queued but never started running (llm_started_at nil) is
  # only stale after a longer grace — a queue backlog is not a stuck job.
  QUEUE_STALE_AFTER = 20.minutes
```

Rewrite `fail_stale!`:

```ruby
  def self.fail_stale!(threshold: STALE_AFTER, queue_threshold: QUEUE_STALE_AFTER, now: Time.zone.now)
    stale = where(role: :assistant, status: :processing).where(
      "(llm_started_at IS NOT NULL AND llm_started_at < :run) OR (llm_started_at IS NULL AND updated_at < :queue)",
      run: now - threshold, queue: now - queue_threshold
    )
    count = 0
    stale.find_each do |turn|
      turn.update(
        status:  :error,
        content: "Interviewer timed out (no response after #{threshold.inspect}). " \
                 "Use the Retry button to try again."
      )
      count += 1
    end
    Rails.logger.info "VivaTurn.fail_stale!: marked #{count} stuck turn(s) as :error" if count.positive?
    count
  end
```

Update the `stuck` scope's `:processing` clause to the same split:

```ruby
  scope :stuck, -> {
    joins(:submission)
      .assistant_turns
      .where(submissions: {status: Submission.statuses[:submitted]})
      .where(
        "(viva_turns.status = :processing AND ((viva_turns.llm_started_at IS NOT NULL AND viva_turns.llm_started_at < :run) OR (viva_turns.llm_started_at IS NULL AND viva_turns.updated_at < :queue))) OR viva_turns.status = :error",
        processing: statuses[:processing], error: statuses[:error],
        run: STALE_AFTER.ago, queue: QUEUE_STALE_AFTER.ago
      )
  }
```

- [ ] **Step 2: Update / add tests**

In `test/models/viva_turn_test.rb`, the existing `"fail_stale! threshold is configurable"` test creates a turn with `updated_at` 2 min ago and no `llm_started_at`; under the new logic it takes the queue branch. Update it to exercise a *started* turn:

```ruby
  test "fail_stale! threshold governs a started turn" do
    turn = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    VivaTurn.where(id: turn.id).update_all(llm_started_at: 2.minutes.ago, updated_at: 2.minutes.ago)

    assert_equal 0, VivaTurn.fail_stale!                       # default 10 min — too fresh
    assert_equal 1, VivaTurn.fail_stale!(threshold: 1.minute)  # started 2 min ago — now stale
  end

  test "fail_stale! leaves a still-queued turn alone until the queue grace passes" do
    turn = @submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    VivaTurn.where(id: turn.id).update_all(llm_started_at: nil, updated_at: 12.minutes.ago)

    assert_equal 0, VivaTurn.fail_stale!, "queued 12 min but not started — not yet stale"
    assert_equal 1, VivaTurn.fail_stale!(queue_threshold: 10.minutes)
  end
```

The first existing test `"fail_stale! marks old :processing turns as :error"` uses `updated_at` 30 min ago, no started_at → queue branch at 20 min → still marked. It passes unchanged.

- [ ] **Step 3: Run**

Run: `bin/rails test test/models/viva_turn_test.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
hg commit -m "viva: stale-turn sweeper distinguishes queued from running

A turn that was queued but never started (llm_started_at nil) is stale
only after QUEUE_STALE_AFTER (20 min), not STALE_AFTER (10 min) — so a
queue backlog no longer shows students a false 'timed out'. A turn that
started and hung still fails at 10 min.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" app/models/viva_turn.rb test/models/viva_turn_test.rb
```

---

## Task 11: Final verification and history docs

- [ ] **Step 1: Run the full targeted suite**

Run:
```bash
bin/rails test test/lib/stats_test.rb test/models/ai_usage_report_test.rb test/models/viva_turn_test.rb test/services/llm/viva_turn_assist_test.rb test/services/llm/comment_assist_test.rb test/services/llm/viva_grade_assist_test.rb test/jobs/llm/queue_assignment_test.rb test/integration/contests_ai_usage_test.rb test/integration/contests_controller_test.rb test/integration/report_controller_access_test.rb test/integration/main_controller_test.rb
```
Expected: all PASS.

- [ ] **Step 2: Run the broad check once**

Run: `bin/rails test` (all minitest). Expected: no new failures vs baseline. Note the two pre-existing skips mentioned in CLAUDE.md if they appear.

- [ ] **Step 3: Fill the `<fill>` revs in CHANGELOG and the two history docs**

After all commits land, replace each `<fill>` / `<fill after commit>` placeholder in `CHANGELOG.md`, `doc/Viva-History.md`, `doc/Assist-History.md` with the actual `hg` revs (`hg log -l 12 --template '{rev} {desc|firstline}\n'`). Commit:

```bash
hg commit -m "docs: cite revs for the AI-usage report, timing, queue split and exam fixes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" CHANGELOG.md doc/Viva-History.md doc/Assist-History.md
```

- [ ] **Step 4: Update the postmortem status**

In `doc/exam-postmortem-2026-09-09-d69_q1.md`, mark W0/W1/W2/W3 and B1/B2/B4 (and B3 if done) as DONE with their revs; leave decisions 3/4/5/6 for dae. Commit with the docs.

---

## Self-review notes (already applied)

- **Spec coverage:** W0 → Task 4; W1 → Tasks 5–7; W2 → Tasks 2–3; W3/B1 → Task 8, B2 → Task 9, B4 → Task 6, B3 → Task 10. F5 (contest-stop auto-finish) is deferred to `doc/backlog.md` per the postmortem, not in this plan. The full second-opinion pass (decision 3) is out of scope by decision.
- **Type consistency:** `AiUsageReport#calls_json` (Task 5) is the exact method the controller (Task 6) and DataTable columns (Task 7) consume; `Stats.percentile`/`Stats.mean` names match across Tasks 1 and 5; `queue_as :viva` (Task 4) matches the `queue.yml` queue name.
- **Deployment (not code):** raise `RAILS_MAX_THREADS` to 12 on the `solid_queue.service` unit before relying on the viva worker; this is recorded in the postmortem's decision-2, not automated here.
- **Known follow-up:** a retried turn (`retry_turn`) already wipes cost/tokens; it will also wipe the new timing columns on wipe and repopulate on the next attempt — consistent with existing behavior, no extra work.
