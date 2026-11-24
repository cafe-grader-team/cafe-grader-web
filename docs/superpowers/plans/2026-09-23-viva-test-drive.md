# Viva Test-Drive Sessions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an editor or admin sit a viva themselves in a session flagged `test_drive`, graded like a real one but excluded from every student-facing list, score, quota and report.

**Architecture:** One boolean column on `submissions`; the existing `Submission.regular` scope widens to "not a shadow AND not a test-drive", so every reader that already uses it excludes test-drives in one change, and the handful of hand-written shadow checks gain the matching condition. A new `VivaSessionsController#test_drive` action shares session creation with `#start`, skips the three student gates, and the edit page gets a button plus a list of test-drives; admin pages badge them.

**Tech Stack:** Ruby 3.4 / Rails 8.0, MySQL 8, HAML, Hotwire (Turbo drive OFF — mutating clicks are `button_to` forms), Bootstrap 5, minitest. **Version control is Mercurial (`hg`), NOT git.**

**Spec:** `docs/superpowers/specs/2026-09-23-viva-test-drive-design.md` — read it first; the plan argues from it.

## Global Constraints

- **hg, not git.** Commit with `hg commit -m "…" <explicit file list>`; never a bare `hg commit`. Before every commit run `hg log -r . --template '{activebookmark}\n'` and confirm it prints `master`; if not, STOP and report.
- Every commit message ends with the trailer line `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` (write the message to a file and use `hg commit -l <file>`).
- Tests must be green before each commit: run the named files, then in Task 4 the full `bin/rails check`.
- Data attributes in HAML/Rails helpers use **flat keys** (`data: {bs_toggle: 'tooltip', bs_title: '…'}`), never nested hashes.
- Server-mutating clicks are `button_to` forms. The header Test-drive button is a plain (non-Turbo) POST that redirects to the new session page; the session-page buttons keep their existing `form: {data: {turbo: true, …}}` shape.
- Icons: `%span.mi icon_name` / `mdi(:icon_name, 'classes')`. Never raw SVG.
- Fixture facts you will rely on: `system.use_problem_group` is `'false'` in fixtures (set it `'true'` for editor tests); `right.user_view_submission` is `'false'`; `viva.practice_daily_start_limit` is `'3'`; `problems(:prob_viva)` (name `viva_problem`, viva type, available, **in no group**); `groups(:group_a)` enabled with `mary` as editor (role 2), `john`/`james` members (role 0), `reba` reporter (role 1); users sign in as `("admin","admin")`, `("mary","mary")`, `("john","hello")`, `("james","morning")`, `("reba","reba")`. There is no `viva` Language fixture: tests create it with `Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }`.
- Scope name: the spec writes `scope :test_drive`; the code uses **`scope :test_drives`** (plural) so the class-level scope cannot be confused with the per-row `test_drive?` reader. Use `Submission.test_drives` everywhere.
- Spec deviation, recorded: the spec lists a badge on `submissions/show`; that page redirects every viva submission to the viva page (`SubmissionsController#show`), so a test-drive can never render there. No change to that view. The badge goes on the viva page, the alerts page and the stuck-turns page.

---

## File structure

| file | responsibility |
|---|---|
| `db/migrate/20260923120000_add_test_drive_to_submissions.rb` (new) | the boolean column |
| `app/models/submission.rb` | `regular` widened; `test_drives` scope; comment |
| `app/models/problem_stat.rb`, `app/controllers/report_controller.rb`, `app/models/ai_usage_report.rb`, `app/models/user.rb` | the hand-written exclusions and the view-rights branch |
| `config/routes.rb` | `POST /problems/:id/viva/test_drive` |
| `app/controllers/viva_sessions_controller.rb` | `#test_drive`; shared `create_viva_session!`; test-drive branches in `#restart` / `#finish` |
| `app/helpers/submissions_helper.rb` | `submission_test_drive_badge` |
| `app/views/problems/edit.html.haml`, `app/views/problems/_form.html.haml`, `app/views/problems/_viva_test_drives.html.haml` (new) | header button; the Test-drives list |
| `app/views/viva_sessions/show.html.haml`, `app/views/graders/viva_alerts.html.haml`, `app/views/graders/stuck_viva_turns.html.haml` | badge / notice / buttons |
| `test/models/test_drive_exclusion_test.rb` (new), `test/integration/viva_sessions_controller_test.rb`, `test/integration/problems_controller_test.rb` | tests |
| `doc/Viva-Exam.md`, `doc/wiki/viva-authoring-guide.md`, `doc/wiki/instructor-viva-guide.md`, `doc/Viva-History.md`, `CHANGELOG.md` | live docs |

---

### Task 1: Column, scope, and the exclusion audit

**Files:**
- Create: `db/migrate/20260923120000_add_test_drive_to_submissions.rb`
- Modify: `app/models/submission.rb:91-98`, `app/models/problem_stat.rb:7`, `app/controllers/report_controller.rb:540,551,593`, `app/models/ai_usage_report.rb:162-164`, `app/models/user.rb:496-505`
- Test: `test/models/test_drive_exclusion_test.rb` (new)

**Interfaces:**
- Produces: column `submissions.test_drive` (boolean, not null, default false) → AR reader `Submission#test_drive?`; `Submission.regular` now excludes `test_drive: true`; `Submission.test_drives` scope. Later tasks rely on all three names.

- [ ] **Step 1: Write the failing test file**

Create `test/models/test_drive_exclusion_test.rb`:

```ruby
# test/models/test_drive_exclusion_test.rb
require 'test_helper'

# Mirrors shadow_exclusion_test.rb for viva test-drives (submissions.test_drive):
# an author's trial run must vanish from every student-facing count, score,
# quota and report, while staying visible to its author and to staff.
# Design: docs/superpowers/specs/2026-09-23-viva-test-drive-design.md
class TestDriveExclusionTest < ActiveSupport::TestCase
  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  setup do
    # Group mode on, and the viva problem placed in group_a, so that mary
    # (editor of group_a) is an editor of the problem and john (member) is
    # one of its students. Fixtures keep prob_viva out of every group.
    set_grader_config('system.use_problem_group', 'true')
    @problem = problems(:prob_viva)
    GroupProblem.create!(group: groups(:group_a), problem: @problem, enabled: true)
    @mary = users(:mary)
    @john = users(:john)

    @drive = Submission.create!(user: @mary, problem: @problem, language: viva_language,
                                status: :done, submitted_at: Time.zone.now, points: 100,
                                test_drive: true)
    @drive.viva_turns.create!(role: :assistant, status: :ok, content: 'Q1?', cost: 0.5)
    @drive.viva_turns.create!(role: :student,   status: :ok, content: 'A1')

    @real = Submission.create!(user: @john, problem: @problem, language: viva_language,
                               status: :done, submitted_at: Time.zone.now, points: 40)
    @real.viva_turns.create!(role: :assistant, status: :ok, content: 'Q1?', cost: 0.5)
    @real.viva_turns.create!(role: :student,   status: :ok, content: 'A1')
  end

  test "regular excludes test-drives; test_drives finds them; shadows stay separate" do
    refute_includes Submission.regular, @drive
    assert_includes Submission.regular, @real
    assert_includes Submission.test_drives, @drive
    refute_includes Submission.test_drives, @real
    refute_includes Submission.shadow, @drive, "a test-drive is not a near-miss shadow"
  end

  test "author, admin and reporter can view a test-drive; a peer cannot, even with transcript sharing on" do
    set_grader_config('right.user_view_submission', 'true')
    @problem.update!(view_submission: true)
    assert @john.can_view_submission?(@real), "sanity: john sees his own real session"
    assert @mary.can_view_submission?(@real), "sanity: the editor sees a student's session"

    assert @mary.can_view_submission?(@drive),         "author sees their own test-drive"
    assert users(:admin).can_view_submission?(@drive), "admin sees every test-drive"
    assert users(:reba).can_view_submission?(@drive),  "reporter of the group sees it"
    refute @john.can_view_submission?(@drive),         "a peer must not, even when the problem shares transcripts"
  end

  test "problem stats exclude test-drives" do
    regular_count = Submission.regular.where(problem_id: @problem.id).count
    stats = @problem.get_submission_stat
    assert_equal regular_count, stats[:total_sub]
    assert_equal 0, stats[:pass], "the test-drive's 100 points must not count as a pass"
  end

  test "problem_stat recompute excludes test-drives" do
    regular_count = Submission.regular.where(problem_id: @problem.id).count
    ProblemStat.recompute_all
    assert_equal regular_count, ProblemStat.find_by(problem_id: @problem.id).sub_count
  end

  test "contest submissions and the AI-usage report exclude test-drives" do
    contest = Contest.create!(name: 'td-test', enabled: true, start: 1.hour.ago, stop: 1.hour.from_now)
    contest.contests_users.create!(user: @mary, enabled: true)
    contest.contests_users.create!(user: @john, enabled: true)
    contest.problems << @problem
    assert_includes contest.submissions, @real
    refute_includes contest.submissions, @drive

    report = AiUsageReport.new(contest)
    assert_equal 1, report.summary[:sessions_opened], "john's real interview counts, mary's test-drive does not"
    assert_equal 1, report.summary[:turns],           "only the real session's LLM call is counted"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/models/test_drive_exclusion_test.rb`
Expected: errors — `unknown attribute 'test_drive' for Submission` (column does not exist yet).

- [ ] **Step 3: Add the migration and run it**

Create `db/migrate/20260923120000_add_test_drive_to_submissions.rb`:

```ruby
# Viva test-drive sessions (design D7, spec 2026-09-23): an editor/admin sits
# their own viva in a session flagged test_drive. Graded like a real session;
# excluded from every student-facing list, quota and report via
# Submission.regular. Appended boolean with a default = instant DDL on MySQL 8.
class AddTestDriveToSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :submissions, :test_drive, :boolean, null: false, default: false
  end
end
```

Run: `bin/rails db:migrate`
Expected: `db/schema.rb` version becomes `2026_09_23_120000` and the `submissions` table gains `t.boolean "test_drive", default: false, null: false`. Check with `grep -n 'test_drive' db/schema.rb`.

- [ ] **Step 4: Widen the scope**

In `app/models/submission.rb` replace this block:

```ruby
  # Near-Miss Grading: shadow submissions are machine-generated repaired
  # copies (repaired_from_id points at the original). Every student-visible
  # query and every quota count must read .regular; the judge worker, admin
  # monitoring, and number-assignment must NOT filter. See the exclusion
  # audit in docs/superpowers/plans/2026-07-30-near-miss-grading.md.
  scope :regular, -> { where(repaired_from_id: nil) }
  scope :shadow,  -> { where.not(repaired_from_id: nil) }
```

with:

```ruby
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
```

- [ ] **Step 5: The hand-written shadow checks**

`app/models/problem_stat.rb` line 7 — replace

```ruby
    rows = Problem.joins("LEFT JOIN submissions ON submissions.problem_id = problems.id AND submissions.repaired_from_id IS NULL")
```

with

```ruby
    rows = Problem.joins("LEFT JOIN submissions ON submissions.problem_id = problems.id AND submissions.repaired_from_id IS NULL AND submissions.test_drive = 0")
```

`app/controllers/report_controller.rb` — three raw-SQL WHERE clauses (two in `cheat_report`, one in `cheat_scrutinize`) end with the exact text `AND s.repaired_from_id IS NULL`. Replace **all three** occurrences of

```
AND s.repaired_from_id IS NULL
```

with

```
AND s.repaired_from_id IS NULL AND s.test_drive = 0
```

Verify: `grep -c 's.test_drive = 0' app/controllers/report_controller.rb` prints `3`.

`app/models/ai_usage_report.rb` — replace

```ruby
  def sub_ids
    @sub_ids ||= Submission.where(problem_id: problem_ids, user_id: user_ids).pluck(:id)
  end
```

with

```ruby
  # .regular: near-miss shadows and author test-drives are not student usage.
  def sub_ids
    @sub_ids ||= Submission.regular.where(problem_id: problem_ids, user_id: user_ids).pluck(:id)
  end
```

`app/models/user.rb`, inside `can_view_submission?` — after the archived-viva block, which ends with

```ruby
    return false if submission.viva_archived_at.present?
```

and before the comment `# check global disable`, insert:

```ruby
    # Viva test-drives are an author's own trial run — rubric probing
    # included. The owner, admins and reporters already returned true above;
    # nobody else may read one, even when the problem shares transcripts.
    return false if submission.test_drive?
```

- [ ] **Step 6: Run the new test file and the two neighbours**

Run: `bin/rails test test/models/test_drive_exclusion_test.rb test/models/shadow_exclusion_test.rb test/models/ai_usage_report_test.rb`
Expected: all PASS, 0 failures.

- [ ] **Step 7: Commit**

Write the message to a file, then commit only these files:

```bash
cat > /tmp/td-task1.txt <<'MSG'
submissions: test_drive flag; Submission.regular excludes viva test-drives

Column submissions.test_drive (boolean, default false). `regular` now means
"not a near-miss shadow and not an author's test-drive", so every
student-facing list, quota and report that reads it excludes test-drives in
one change; the hand-written shadow checks (cheat report raw SQL x3,
ProblemStat join, AiUsageReport.sub_ids) gain the matching condition, and
can_view_submission? denies test-drives to peers even under transcript
sharing (owner, admins, reporters keep access). Spec:
docs/superpowers/specs/2026-09-23-viva-test-drive-design.md.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
test "$(hg log -r . --template '{activebookmark}')" = master || { echo "NOT ON MASTER"; exit 1; }
hg add db/migrate/20260923120000_add_test_drive_to_submissions.rb test/models/test_drive_exclusion_test.rb
hg commit -l /tmp/td-task1.txt \
  db/migrate/20260923120000_add_test_drive_to_submissions.rb db/schema.rb \
  app/models/submission.rb app/models/problem_stat.rb app/controllers/report_controller.rb \
  app/models/ai_usage_report.rb app/models/user.rb test/models/test_drive_exclusion_test.rb
```

---

### Task 2: The test-drive start path (controller + route)

**Files:**
- Modify: `config/routes.rb:160` (problems member block), `app/controllers/viva_sessions_controller.rb` (`before_action :set_problem`, `#start` tail, new `#test_drive`, `#restart`, `#finish`, new private `create_viva_session!`)
- Test: `test/integration/viva_sessions_controller_test.rb` (append)

**Interfaces:**
- Consumes (Task 1): `Submission.test_drives`, `Submission.regular`, `Submission#test_drive?`, attribute `test_drive:` on create.
- Produces: route helper `viva_test_drive_problem_path(problem)` → `POST /problems/:id/viva/test_drive`; private `create_viva_session!(problem, test_drive: false)` returning the new `Submission`. Task 3's views call the route helper.

- [ ] **Step 1: Append the failing tests**

Append inside `class VivaSessionsControllerTest` (before its final `end`), in `test/integration/viva_sessions_controller_test.rb`:

```ruby
  # --- test_drive: an author sits their own viva (spec 2026-09-23-viva-test-drive-design) ---

  # Group mode on and prob_viva placed in group_a, so mary (editor of group_a)
  # may test-drive it while john (member) is a plain student of it. Fixtures
  # keep prob_viva out of every group and use_problem_group off.
  def setup_test_drive_problem(viva_daily_limit: nil)
    viva_language  # seed the 'viva' Language: #start and #test_drive refuse without it
    set_grader_config('system.use_problem_group', 'true')
    problem = problems(:prob_viva)
    GroupProblem.create!(group: groups(:group_a), problem: problem, enabled: true)
    problem.update!(viva_prompt: "# Rubric\nBe fair.", viva_daily_limit: viva_daily_limit)
    problem
  end

  # An open test-drive with settled turns (no :processing placeholder), so
  # restart/finish are not refused as "busy".
  def make_test_drive(user:, problem:, answered: true)
    Submission.create!(user: user, problem: problem, language: viva_language,
                       status: :submitted, submitted_at: Time.zone.now, test_drive: true).tap do |sub|
      sub.viva_turns.create!(role: :assistant, status: :ok, content: 'Q1?')
      sub.viva_turns.create!(role: :student,   status: :ok, content: 'A1') if answered
    end
  end

  test "test_drive by an editor of the problem's group creates a flagged session and opens it" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    assert_difference -> { Submission.test_drives.count }, 1 do
      assert_enqueued_with(job: Llm::VivaTurnAssistJob) do
        post viva_test_drive_problem_path(problem)
      end
    end
    drive = Submission.test_drives.order(:id).last
    assert_redirected_to viva_submission_path(drive)
    assert_equal users(:mary), drive.user
    assert drive.test_drive?
    assert_equal %w[system assistant], drive.viva_turns.ordered.map(&:role), "greeting placeholder queued like a real start"
    refute_includes Submission.regular, drive
  end

  test "test_drive is refused for a student who is not an editor of the problem" do
    problem = setup_test_drive_problem
    sign_in_as("john", "hello")
    assert_no_difference -> { Submission.count } do
      post viva_test_drive_problem_path(problem)
    end
    assert_redirected_to list_main_path
    assert_match(/only editors/, flash[:alert])
  end

  test "test_drive skips the daily start limit that refuses a real start" do
    set_grader_config("viva.practice_daily_start_limit", 1)
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    # one engaged, archived real session today uses up mary's single start
    used = Submission.create!(user: users(:mary), problem: problem, language: viva_language,
                              status: :submitted, submitted_at: Time.zone.now, viva_archived_at: Time.zone.now)
    used.viva_turns.create!(role: :student, status: :ok, content: 'answered once')

    post viva_start_problem_path(problem)
    assert_redirected_to list_main_path
    assert_match(/Daily practice limit/, flash[:alert])

    assert_difference -> { Submission.test_drives.count }, 1 do
      post viva_test_drive_problem_path(problem)
    end
  end

  test "test_drive skips the contest-only rule that refuses a real start" do
    problem = setup_test_drive_problem(viva_daily_limit: 0)
    sign_in_as("mary", "mary")
    post viva_start_problem_path(problem)
    assert_redirected_to list_main_path
    assert_match(/only be taken during a contest/, flash[:alert])

    assert_difference -> { Submission.test_drives.count }, 1 do
      post viva_test_drive_problem_path(problem)
    end
  end

  test "a second test_drive click reopens the open test-drive instead of starting another" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    post viva_test_drive_problem_path(problem)
    first = Submission.test_drives.order(:id).last
    assert_no_difference -> { Submission.count } do
      post viva_test_drive_problem_path(problem)
    end
    assert_redirected_to viva_submission_path(first)
    assert_match(/already have an open test-drive/, flash[:notice])
  end

  test "an open test-drive does not block the author's real start" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    make_test_drive(user: users(:mary), problem: problem)
    assert_difference -> { Submission.regular.where(user: users(:mary), problem: problem).count }, 1 do
      post viva_start_problem_path(problem)
    end
  end

  test "restart on a test-drive archives it and opens a fresh test-drive at once" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    drive = make_test_drive(user: users(:mary), problem: problem)
    assert_difference -> { Submission.test_drives.count }, 1 do
      post viva_restart_submission_path(drive)
    end
    fresh = Submission.test_drives.order(:id).last
    assert_not_equal drive.id, fresh.id
    assert_redirected_to viva_submission_path(fresh)
    assert drive.reload.viva_archived_at.present?, "the old test-drive is archived"
    assert fresh.test_drive?
  end

  test "finish is allowed on a contest-only test-drive" do
    problem = setup_test_drive_problem(viva_daily_limit: 0)
    sign_in_as("mary", "mary")
    drive = make_test_drive(user: users(:mary), problem: problem, answered: true)
    assert_enqueued_with(job: Llm::VivaGradeAssistJob) do
      post viva_finish_submission_path(drive)
    end
    assert_redirected_to viva_submission_path(drive)
    assert_predicate drive.reload, :evaluating?
  end

  test "test_drive on a code problem sends the editor back to the edit page" do
    set_grader_config('system.use_problem_group', 'true')
    sign_in_as("mary", "mary")   # mary edits group_a, which holds prob_add
    assert_no_difference -> { Submission.count } do
      post viva_test_drive_problem_path(problems(:prob_add))
    end
    assert_redirected_to edit_problem_path(problems(:prob_add))
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/integration/viva_sessions_controller_test.rb`
Expected: the new tests error with `undefined method 'viva_test_drive_problem_path'`; every pre-existing test still passes.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `resources :problems … member do` block, directly under

```ruby
      post 'viva/start', to: 'viva_sessions#start', as: 'viva_start'
```

add

```ruby
      post 'viva/test_drive', to: 'viva_sessions#test_drive', as: 'viva_test_drive'
```

- [ ] **Step 4: Controller — before_action, shared creation, the new action**

In `app/controllers/viva_sessions_controller.rb`:

(a) change

```ruby
  before_action :set_problem, only: %i[start]
```
to
```ruby
  before_action :set_problem, only: %i[start test_drive]
```

(b) In `#start`, replace its tail — from `    submission = nil` through `    redirect_to viva_submission_path(submission)` (the `Submission.transaction do … end` block, the `Llm::VivaTurnAssistJob.perform_later` line and the redirect) — with:

```ruby
    submission = create_viva_session!(@problem)
    redirect_to viva_submission_path(submission)
```

(c) Directly after `#start`'s closing `end` (before the `# GET /submissions/:submission_id/viva` comment of `#show`), add:

```ruby
  # POST /problems/:problem_id/viva/test_drive
  #
  # Author's test-drive (design D7; spec 2026-09-23-viva-test-drive-design):
  # an editor of the problem's group, or an admin, sits the viva in a session
  # flagged submissions.test_drive. The interview and grading run exactly as
  # for a student; the flag keeps the session out of every report, score,
  # cost figure and quota (Submission.regular excludes it) and out of the
  # three student gates #start applies — the daily start limit, the
  # contest-only rule, and the one-active-session guard, which here looks at
  # test-drives only: a second click while one is open just reopens it.
  # The setup check stays: a viva with no briefing cannot assemble a prompt.
  def test_drive
    unless @problem.viva_exam?
      redirect_to edit_problem_path(@problem), alert: 'This problem is not a viva exam.' and return
    end
    unless @current_user.can_edit_problem?(@problem)
      redirect_to list_main_path, alert: 'Authorization error: only editors of this problem may test-drive it.' and return
    end
    unless Language.find_by(name: VIVA_LANGUAGE_NAME)
      redirect_to edit_problem_path(@problem), alert: 'Viva language is not seeded. Run Language.seed.' and return
    end
    setup_errors = @problem.viva_setup_errors
    if setup_errors.any?
      redirect_to edit_problem_path(@problem),
                  alert: "Cannot test-drive '#{@problem.name}' — problem setup is incomplete: #{setup_errors.join('; ')}"
      return
    end

    open_drive = @problem.submissions.test_drives.where(user: @current_user, viva_archived_at: nil).order(:id).last
    if open_drive
      redirect_to viva_submission_path(open_drive),
                  notice: 'You already have an open test-drive on this problem — continuing it.'
      return
    end

    submission = create_viva_session!(@problem, test_drive: true)
    redirect_to viva_submission_path(submission),
                notice: 'Test-drive started — this session is excluded from reports, cost figures and start limits.'
  end
```

(d) In the `private` section, directly after `force_finish!`'s closing `end` (so the existing comment block above `daily_start_limit_for` / `engaged_starts_today` stays attached to those methods), add:

```ruby
  # Creates a viva session for @current_user on `problem` and kicks off the
  # greeting: the Submission row, the "(interview start)" system turn, the
  # :processing assistant placeholder, and Llm::VivaTurnAssistJob once the
  # transaction has committed. Shared by #start (real sessions), #test_drive
  # and the test-drive branch of #restart, so the three can never drift.
  def create_viva_session!(problem, test_drive: false)
    submission = nil
    placeholder = nil
    Submission.transaction do
      submission = Submission.create!(
        user:     @current_user,
        problem:  problem,
        language: Language.find_by!(name: VIVA_LANGUAGE_NAME),
        source:   nil,
        source_filename: nil,
        status:   :submitted,
        submitted_at: Time.zone.now,
        ip_address: request.remote_ip,
        test_drive: test_drive
      )
      submission.viva_turns.create!(role: :system, status: :ok, content: '(interview start)')
      placeholder = submission.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    end
    Llm::VivaTurnAssistJob.perform_later(submission, turn: placeholder)
    submission
  end

```

- [ ] **Step 5: Controller — restart and finish branches**

(e) Replace the whole body of `def restart … end` so the check-and-archive runs under the same row lock `#answer` / `#finish` take (a double click used to be harmless while restart only archived; the test-drive branch now CREATES a session, so the second click must be refused, not doubled). User-facing messages are unchanged:

```ruby
  def restart
    unless @current_user == @submission.user
      redirect_to viva_submission_path(@submission), alert: 'Only the owner can restart their viva.' and return
    end
    # Non-viva submissions must never be archivable this way: archiving
    # hides a submission from main_controller's canonical max(id) pick — a
    # grade-manipulation vector if it could be triggered on an ordinary
    # coding submission.
    unless @submission.problem.viva_exam?
      redirect_to viva_submission_path(@submission), alert: 'Restart is only available for viva exam problems.' and return
    end

    # Same row lock as #answer / #finish. Two concurrent Restart clicks used
    # to both pass the not-archived check — harmless while restart only
    # archived (idempotent), but a test-drive restart now CREATES a fresh
    # session, so the second click must be refused, not doubled. The fresh
    # session is created after the lock block has committed.
    outcome = @submission.with_lock do
      next :archived if @submission.viva_archived_at.present?
      next :busy     if @submission.viva_turns.where(status: :processing).exists?
      @submission.update!(viva_archived_at: Time.zone.now)
      :restarted
    end

    case outcome
    when :archived
      redirect_to viva_submission_path(@submission), alert: 'This viva session has already been archived.'
    when :busy
      redirect_to viva_submission_path(@submission), alert: 'Wait for the current response to finish first.'
    when :restarted
      problem = @submission.problem
      if @submission.test_drive?
        # Test-drives restart in place: archive, then open a fresh test-drive
        # at once — no limit, no detour through the problem list.
        fresh = create_viva_session!(problem, test_drive: true)
        redirect_to viva_submission_path(fresh), notice: 'Test-drive restarted — the previous session is archived.'
      elsif problem.viva_daily_limit == 0
        redirect_to list_main_path, notice: 'Viva archived — start a fresh one from the problem list (only available during a contest).'
      else
        redirect_to list_main_path, notice: "Viva archived — start a fresh one from the problem list (limit #{daily_start_limit_for(problem)} per day)."
      end
    end
  end
```

Covering test (appended with the other test-drive tests; uses the file's existing `SubmissionLockHook`):

```ruby
  test "restart on a test-drive does not open a second session when a concurrent restart archived it first" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    drive = make_test_drive(user: users(:mary), problem: problem)
    # The other click archived this test-drive (and opened its own fresh one) while this one waited for the lock.
    SubmissionLockHook.once = ->(s) { Submission.find(s.id).update_columns(viva_archived_at: Time.zone.now) }

    assert_no_enqueued_jobs(only: Llm::VivaTurnAssistJob) do
      assert_no_difference -> { Submission.test_drives.count } do
        post viva_restart_submission_path(drive)
      end
    end
    assert_redirected_to viva_submission_path(drive)
    assert_match(/already been archived/i, flash[:alert])
    assert_nil SubmissionLockHook.once, "restart must take the row lock (the hook never ran)"
  end
```

(f) In `#finish`, replace

```ruby
    if @submission.problem.viva_daily_limit == 0
      redirect_to viva_submission_path(@submission), alert: 'Contest vivas cannot be ended early.' and return
    end
```

with

```ruby
    if @submission.problem.viva_daily_limit == 0 && !@submission.test_drive?
      redirect_to viva_submission_path(@submission), alert: 'Contest vivas cannot be ended early.' and return
    end
```

- [ ] **Step 6: Run the controller tests**

Run: `bin/rails test test/integration/viva_sessions_controller_test.rb test/models/test_drive_exclusion_test.rb`
Expected: all PASS (the 9 new tests and every pre-existing one), 0 failures.

Then: `bundle exec rubocop app/controllers/viva_sessions_controller.rb config/routes.rb test/integration/viva_sessions_controller_test.rb`
Expected: no offenses.

- [ ] **Step 7: Commit**

```bash
cat > /tmp/td-task2.txt <<'MSG'
viva: test_drive action — an editor/admin sits their own viva outside limits and reports

POST /problems/:id/viva/test_drive (User#can_edit_problem?) creates a
session flagged test_drive through the new shared create_viva_session!,
which #start now uses too. A test-drive skips the daily start limit, the
contest-only rule and the one-active-session guard (a second click reopens
the open test-drive); it keeps the setup check. Restart on a test-drive
archives it and opens a fresh one at once; finish is allowed on
contest-only test-drives. Spec: 2026-09-23-viva-test-drive-design.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
test "$(hg log -r . --template '{activebookmark}')" = master || { echo "NOT ON MASTER"; exit 1; }
hg commit -l /tmp/td-task2.txt config/routes.rb app/controllers/viva_sessions_controller.rb test/integration/viva_sessions_controller_test.rb
```

---

### Task 3: UI — edit-page button and list, session-page badge and controls, admin badges

**Files:**
- Modify: `app/helpers/submissions_helper.rb`, `app/views/problems/edit.html.haml:14-16`, `app/views/problems/_form.html.haml:41`, `app/views/viva_sessions/show.html.haml:27-63`, `app/views/graders/viva_alerts.html.haml:41-44`, `app/views/graders/stuck_viva_turns.html.haml:44`
- Create: `app/views/problems/_viva_test_drives.html.haml`
- Test: `test/integration/problems_controller_test.rb` (append), `test/integration/viva_sessions_controller_test.rb` (append)

**Interfaces:**
- Consumes (Task 1/2): `Submission.test_drives`, `Submission#test_drive?`, `viva_test_drive_problem_path`.
- Produces: helper `submission_test_drive_badge(submission)` (returns `nil` for real submissions, a `<span class="badge text-bg-info ms-1">test-drive</span>` otherwise); partial `problems/_viva_test_drives` taking local `problem`.

- [ ] **Step 1: Append the failing view tests**

In `test/integration/problems_controller_test.rb`, before the class's final `end`:

```ruby
  # --- viva test-drive controls on the edit page (spec 2026-09-23-viva-test-drive-design) ---

  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  test "edit page offers Test-drive on a viva problem and lists existing test-drives" do
    sign_in_as("admin", "admin")
    problem = problems(:prob_viva)
    drive = Submission.create!(user: users(:admin), problem: problem, language: viva_language,
                               status: :done, submitted_at: Time.zone.now, points: 73, test_drive: true)
    get edit_problem_path(problem)
    assert_response :success
    assert_match(%r{/problems/#{problem.id}/viva/test_drive}, response.body, "Test-drive button posts to the test_drive route")
    assert_match(/Test-drives/, response.body, "Test-drives list section is rendered")
    assert_match(%r{/submissions/#{drive.id}/viva}, response.body, "existing test-drive is linked")
  end

  test "edit page has no Test-drive control on a code problem" do
    sign_in_as("admin", "admin")
    get edit_problem_path(problems(:prob_add))
    assert_response :success
    assert_no_match(%r{/viva/test_drive}, response.body)
  end
```

In `test/integration/viva_sessions_controller_test.rb`, before the class's final `end` (after the Task 2 tests; they share `setup_test_drive_problem` and `make_test_drive`):

```ruby
  test "show marks a test-drive with the badge and the unlimited-restarts line" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    drive = make_test_drive(user: users(:mary), problem: problem)
    get viva_submission_path(drive)
    assert_response :success
    assert_match(/>test-drive</, response.body, "badge")
    assert_match(/unlimited restarts/, response.body)
    assert_match(/Restart test-drive/, response.body)
    assert_no_match(/starts left today/, response.body)
  end

  test "the viva alerts and stuck-turn pages badge a test-drive" do
    problem = setup_test_drive_problem
    drive = make_test_drive(user: users(:mary), problem: problem)
    drive.viva_turns.create!(role: :assistant, status: :ok, content: 'flagged', alerted: true)
    stuck = drive.viva_turns.create!(role: :assistant, status: :error, content: 'boom')
    VivaTurn.where(id: stuck.id).update_all(updated_at: 2.hours.ago)  # VivaTurn.stuck may require age; backdate to be safe
    sign_in_as("admin", "admin")
    get viva_alerts_grader_processes_path
    assert_response :success
    assert_match(/>test-drive</, response.body)
    get stuck_viva_turns_grader_processes_path
    assert_response :success
    assert_match(/>test-drive</, response.body)
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/integration/problems_controller_test.rb test/integration/viva_sessions_controller_test.rb`
Expected: the four new tests FAIL on the missing markup (`/viva/test_drive`, `>test-drive<`); everything else passes.

- [ ] **Step 3: The badge helper**

In `app/helpers/submissions_helper.rb`, add inside `module SubmissionsHelper` (after `llm_assist_price_sentence`):

```ruby

  # "test-drive" badge for staff surfaces (viva session page, viva alerts,
  # stuck turns). An author's trial run of a viva — graded like a real
  # session but excluded from reports, cost figures and start limits.
  # Renders nothing for a real submission.
  def submission_test_drive_badge(submission)
    return unless submission.test_drive?
    content_tag :span, 'test-drive', class: 'badge text-bg-info ms-1',
                title: 'Author test-drive — excluded from reports, cost figures and start limits'
  end
```

- [ ] **Step 4: Edit page header button**

In `app/views/problems/edit.html.haml`, inside `.d-flex.gap-2.align-items-center{'data-controller': 'init-ui-component'}`, insert **before** the `= link_to stat_problem_path(@problem), …` line (same indentation, 4 spaces):

```haml
    -# Test-drive (viva only): sit this viva yourself in a session flagged
    -# test_drive — excluded from reports, cost figures and start limits.
    -# Lives here, outside the ONE problem form, because a nested form is
    -# invalid HTML. Labeled like Help: authors must be able to find it.
    - if @problem.viva_exam?
      = button_to viva_test_drive_problem_path(@problem), class: 'btn btn-sm bg-white shadow-sm border-0 text-secondary d-inline-flex align-items-center gap-1', form: {class: 'd-inline'}, data: {bs_toggle: 'tooltip', bs_title: 'Take this viva yourself in a test session — excluded from reports, cost figures and start limits'} do
        %span.mi play_circle
        Test-drive
```

- [ ] **Step 5: The Test-drives list**

Create `app/views/problems/_viva_test_drives.html.haml`:

```haml
-# Test-drive sessions of this viva (author trial runs, submissions.test_drive):
-# a read-only list. The button that starts one is in the page header, outside
-# the problem form. Rendered only in the viva layout of _form (not in the
-# inline block shown while switching a code problem to viva).
-# Design: docs/superpowers/specs/2026-09-23-viva-test-drive-design.md
- drives = problem.persisted? ? problem.submissions.test_drives.includes(:user).order(id: :desc).limit(10).to_a : []
%section.mb-4
  %h5.fw-bold.text-body-emphasis.mb-3.pb-2.border-bottom Test-drives
  - if drives.empty?
    %p.small.text-secondary.mb-0
      No test-drives yet — use the
      %strong Test-drive
      button above to sit this viva yourself. Test-drives are graded like a real session but excluded from reports, cost figures and start limits.
  - else
    %table.table.table-sm.table-hover.align-middle.mb-1
      %thead
        %tr
          %th Author
          %th Started
          %th Status
          %th.text-end Points
          %th
      %tbody
        - drives.each do |sub|
          %tr
            %td= sub.user&.login
            %td.text-secondary.small= "#{time_ago_in_words(sub.submitted_at)} ago"
            %td
              = sub.status
              - if sub.viva_archived?
                %span.badge.text-bg-warning.ms-1 archived
            %td.text-end= sub.points.nil? ? '—' : sub.points.to_i
            %td.text-end= link_to 'Open', viva_submission_path(sub), class: 'btn btn-sm btn-outline-primary border-0 py-0'
    %p.small.text-secondary.mb-0 Newest 10 shown. Test-drives are excluded from reports, cost figures and start limits.
```

In `app/views/problems/_form.html.haml`, in the viva layout card, directly after

```haml
              = render 'viva_fields', form: form, problem: problem
```

(the one inside `.col-md-6{data: {viva_exam_toggle_target: 'showForViva'}}`, **not** the one in `_general_fields.html.haml`) add, same indentation:

```haml
              = render 'viva_test_drives', problem: problem
```

- [ ] **Step 6: Viva session page**

In `app/views/viva_sessions/show.html.haml`:

(a) Status row — replace

```haml
            = @submission.status
            - if @submission.viva_archived?
              %span.badge.text-bg-warning.ms-1 archived
```
with
```haml
            = @submission.status
            - if @submission.viva_archived?
              %span.badge.text-bg-warning.ms-1 archived
            = submission_test_drive_badge(@submission)
```

(b) Starts row — replace

```haml
            - if @current_user == @submission.user && @current_user.admin?
              | Unlimited starts (admin)
            - elsif @submission.problem.viva_daily_limit == 0
              | Contest-only viva — starts are governed by the contest
```
with
```haml
            - if @submission.test_drive?
              Test-drive — unlimited restarts; excluded from reports, cost figures and start limits
            - elsif @current_user == @submission.user && @current_user.admin?
              Unlimited starts (admin)
            - elsif @submission.problem.viva_daily_limit == 0
              Contest-only viva — starts are governed by the contest
```

(No leading `|`: in HAML a line that *starts* with a pipe is plain text, so the two pre-existing lines printed a stray "| " — found in the controller's render check; fixed in the same hunk. Guard assertions `assert_no_match(/\|\s*Test-drive/, …)` and `assert_no_match(/\|\s*Unlimited starts/, …)` go in the test-drive show test and the existing admin-unlimited test.)

(c) Owner buttons — replace the block

```haml
        - if @current_user == @submission.user && @submission.viva_archived_at.nil?
          - if @submission.status.to_s == 'submitted' && @submission.problem.viva_daily_limit != 0 && @submission.viva_turns.where(role: :student).exists?
            = button_to 'End interview & get graded', viva_finish_submission_path(@submission),
                class: 'btn btn-sm btn-success mt-2 me-1',
                form: {class: 'd-inline', data: {turbo: true, 'turbo-confirm': 'End the interview now and get graded? Topics not yet discussed will score zero.'}}
          = button_to 'Restart practice viva', viva_restart_submission_path(@submission),
              class: 'btn btn-sm btn-warning mt-2',
              form: {class: 'd-inline', data: {turbo: true, 'turbo-confirm': 'Archive this session and start over? The transcript is kept for instructors.'}}
```
with
```haml
        - if @current_user == @submission.user && @submission.viva_archived_at.nil?
          - if @submission.status.to_s == 'submitted' && (@submission.problem.viva_daily_limit != 0 || @submission.test_drive?) && @submission.viva_turns.where(role: :student).exists?
            = button_to 'End interview & get graded', viva_finish_submission_path(@submission),
                class: 'btn btn-sm btn-success mt-2 me-1',
                form: {class: 'd-inline', data: {turbo: true, 'turbo-confirm': 'End the interview now and get graded? Topics not yet discussed will score zero.'}}
          - if @submission.test_drive?
            = button_to 'Restart test-drive', viva_restart_submission_path(@submission),
                class: 'btn btn-sm btn-warning mt-2',
                form: {class: 'd-inline', data: {turbo: true, 'turbo-confirm': 'Archive this test-drive and open a fresh one right away?'}}
          - else
            = button_to 'Restart practice viva', viva_restart_submission_path(@submission),
                class: 'btn btn-sm btn-warning mt-2',
                form: {class: 'd-inline', data: {turbo: true, 'turbo-confirm': 'Archive this session and start over? The transcript is kept for instructors.'}}
```

- [ ] **Step 7: Admin pages**

`app/views/graders/viva_alerts.html.haml` — replace

```haml
              %td
                = sub.status
                - if sub.viva_archived?
                  %span.badge.text-bg-warning.ms-1 archived
```
with
```haml
              %td
                = sub.status
                - if sub.viva_archived?
                  %span.badge.text-bg-warning.ms-1 archived
                = submission_test_drive_badge(sub)
```

`app/views/graders/stuck_viva_turns.html.haml` — replace

```haml
              %td= link_to "##{sub.id}", viva_submission_path(sub), class: 'fw-medium text-primary text-decoration-none'
```
with
```haml
              %td
                = link_to "##{sub.id}", viva_submission_path(sub), class: 'fw-medium text-primary text-decoration-none'
                = submission_test_drive_badge(sub)
```

- [ ] **Step 8: Run the tests**

Run: `bin/rails test test/integration/problems_controller_test.rb test/integration/viva_sessions_controller_test.rb test/models/test_drive_exclusion_test.rb`
Expected: all PASS, 0 failures.

Then: `bundle exec rubocop app/helpers/submissions_helper.rb test/integration/problems_controller_test.rb`
Expected: no offenses.

- [ ] **Step 9: Commit**

```bash
cat > /tmp/td-task3.txt <<'MSG'
viva: Test-drive button + list on the problem edit page; badge and controls on staff pages

Header pill "Test-drive" (viva problems only; outside the problem form) and
a read-only Test-drives section in the Viva Exam card (author, started,
status, points, link; newest 10). The viva session page shows a test-drive
badge, an "unlimited restarts" line instead of the daily countdown, a
"Restart test-drive" button and End interview even on contest-only vivas.
The viva alerts and stuck-turn pages badge test-drives rather than hide
them. Spec: 2026-09-23-viva-test-drive-design.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
test "$(hg log -r . --template '{activebookmark}')" = master || { echo "NOT ON MASTER"; exit 1; }
hg add app/views/problems/_viva_test_drives.html.haml
hg commit -l /tmp/td-task3.txt \
  app/helpers/submissions_helper.rb app/views/problems/edit.html.haml app/views/problems/_form.html.haml \
  app/views/problems/_viva_test_drives.html.haml app/views/viva_sessions/show.html.haml \
  app/views/graders/viva_alerts.html.haml app/views/graders/stuck_viva_turns.html.haml \
  test/integration/problems_controller_test.rb test/integration/viva_sessions_controller_test.rb
```

---

### Task 4: Live docs, changelog, full check

**Files:**
- Modify: `doc/Viva-Exam.md` (new section before `# Jailbreak Detection & Consequence Policy`; Known Gaps D7 line; Phase B bullet), `doc/wiki/viva-authoring-guide.md` (section 8 paragraph + pitfalls row), `doc/wiki/instructor-viva-guide.md` (subsection at the end of "Authoring a viva problem"), `doc/Viva-History.md` (entry under `## Entries`), `CHANGELOG.md` (`[Unreleased]` → `### Added`, first bullet)

**Interfaces:** none (documentation). Use the rev number of Task 3's commit where the text says `<REV3>` (`hg log -r . --template '{rev}'` right after Task 3's commit; Task 1/2 revs are `<REV1>`/`<REV2>`).

- [ ] **Step 1: Run the full project check first**

Run: `bin/rails check`
Expected: minitest 0 failures / 0 errors, RSpec 0 failures, `swagger:verify … up to date`. If anything fails, fix it before touching docs and report what it was.

- [ ] **Step 2: `doc/Viva-Exam.md`**

(a) Insert this section immediately **before** the line `# Jailbreak Detection & Consequence Policy (design D3)`:

```markdown
# Test-Drive Sessions (design D7, shipped 2026-09-23)

An editor of the problem's group, or an admin, can sit a viva themselves in a
session flagged `submissions.test_drive` — the **Test-drive** button in the
problem edit page's header (viva problems only). Design:
`docs/superpowers/specs/2026-09-23-viva-test-drive-design.md`; revs <REV1>–<REV3>.

- **Same interview, same grading.** Prompt assembly, models, alert detection and
  the grade record are exactly those of a student session; what the author sees
  is what a student would see.
- **Excluded everywhere that counts.** `Submission.regular` now means "not a
  near-miss shadow and not a test-drive", so the main list, scores, contest
  scoreboards, every Report page, the problem/user stat pages, the AI-usage
  report and the API exclude test-drives in one place. Hand-written SQL over
  `viva_turns` / `viva_grades` must join `submissions` and filter
  `test_drive = 0` (and `repaired_from_id IS NULL`) itself.
- **Outside the student gates.** A test-drive skips the daily start limit, the
  contest-only rule (`viva_daily_limit = 0`) and the one-active-session guard —
  a second click while a test-drive is open reopens it. It keeps the setup
  check (`viva_setup_errors`). An open test-drive never blocks the author's own
  real start, and never consumes one of their real daily starts.
- **Restart and End.** Restart archives the test-drive and opens a fresh one at
  once; End interview is available even on contest-only vivas.
- **Who sees them.** The author, admins and reporters/editors of the problem's
  groups (via the `:report` arm of `can_view_submission?`). Other students never
  do, even when the problem shares transcripts. Where to find them: the
  Test-drives list in the Viva Exam card of the edit page (newest 10); the viva
  session page, the viva alerts page and the stuck-turns page badge them.
- **Reapers and batch buttons.** "Finish open vivas" (contest page, rev 2161)
  reads the contest's `.regular` submissions and leaves test-drives alone; the
  24 h abandoned-session reaper does not filter and will grade a forgotten
  test-drive a day later (one grade call, accepted).
- **Phase B requirement.** When the exam-strict alert consequence is re-keyed to
  the governing contest, a test-drive must always take the practice (log-only)
  branch, whatever contest it runs inside.

```

(b) In `# Known Gaps`, replace the D7 bullet

```markdown
- **D7 authoring validation (test-drive + preflight lint) is designed but not implemented.** There is no "take your own viva as a test session excluded from reports/limits" flow and no LLM-based lint pass over the assembled prompt yet. The inoculation incident above is exactly the kind of thing the planned lint would catch pre-emptively.
```
with
```markdown
- **D7 authoring validation — half done.** The *test-drive* half shipped 2026-09-23 (see "Test-Drive Sessions"). The *preflight lint* half — an LLM pass over the assembled prompt for rubric leakage, contradictions with the security directive, a missing `# Rubric`, banned template literals and embedded operational instructions — is still not built. The inoculation incident above is exactly the kind of thing that lint would catch pre-emptively.
```

(c) In `## Phase B (planned, not yet implemented)`, append this bullet after the **Window-end force-finish** bullet:

```markdown
- **Test-drives stay practice** *(added 2026-09-23)* — a session flagged `test_drive` must take the practice (log-only) alert branch and no retake budget, whatever contest window it runs inside; the snapshot must record it as ungoverned.
```

- [ ] **Step 3: `doc/wiki/viva-authoring-guide.md`**

(a) In `## 8. Step 6 — Pilot before students see it`, insert as the section's first paragraph (directly under the heading):

```markdown
**Sit it yourself first.** The problem edit page has a **Test-drive** button
(viva problems only, editors and admins). It opens a real interview with the
real examiner and grader, but the session is flagged as a test-drive: it does
not appear in any report or score table, its cost is not counted as student
spend, it does not use up your daily starts, and it can be restarted without
limit. Take at least two test-drives before students see the viva — one
answering as a strong student, one as a weak or evasive one — and read the
grade narrative each time. Your test-drives are listed under **Test-drives** in
the Viva Exam card of the edit page.
```

(b) In `## 10. Pitfalls catalogue`, append this row to the end of the table:

```markdown
| Rubric wording or a probe only turns out to be confusing once real students hit it | Viva published without anyone sitting it | Take two test-drives first — strong and weak student — via the edit page's Test-drive button; read both narratives (authoring) |
```

- [ ] **Step 4: `doc/wiki/instructor-viva-guide.md`**

Insert immediately **before** the line `## Conduct profiles`:

```markdown
### Test-driving a viva

Before students see a viva, sit it yourself. The problem edit page shows a
**Test-drive** button for viva problems (editors of the problem's group and
admins). It starts a normal interview with the normal examiner and grader,
but the session is marked as a test-drive: it is left out of every report,
score table and cost figure, it does not count against your daily starts,
and you can restart it as often as you like. Test-drives are listed under
**Test-drives** in the Viva Exam card of the edit page; students cannot see
them, even on problems that share transcripts.

```

- [ ] **Step 5: `doc/Viva-History.md`**

Insert directly after the line `## Entries` and its blank line (i.e. as the newest entry, above the 2026-09-23 "Finish open vivas" entry):

```markdown
### 2026-09-23 — Test-drive sessions: authors sit their own viva outside limits and reports
**behavior + access policy** · revs <REV1>–<REV3> (master); spec `docs/superpowers/specs/2026-09-23-viva-test-drive-design.md`; D7 (2026-07-20 readiness spec) half done
- **Problem observed:** the only real check of an LLM examiner is to sit the viva, but an author's trial session was a real submission — on the stat page, in every report and the AI-usage figures, burning a daily start (editors, not admins) and sitting among student transcripts. Authors polluted the data or tested less than they should. Listed in `doc/Viva-Exam.md` Known Gaps since 2026-07-21.
- **Change:** `submissions.test_drive`; `Submission.regular` now excludes test-drives as well as near-miss shadows, so every student-facing list, quota and report drops them in one change (hand-written shadow checks in the cheat report, `ProblemStat` and `AiUsageReport` gained the same condition). `POST /problems/:id/viva/test_drive` (editors of the problem's group, admins) shares session creation with the student start but skips the daily limit, the contest-only rule and the one-active-session guard; restart opens a fresh test-drive at once; End is allowed on contest-only vivas. `can_view_submission?` denies test-drives to peers even under transcript sharing. UI: header **Test-drive** pill and a Test-drives list on the problem edit page; badge + "unlimited restarts" line on the session page; badges on the viva alerts and stuck-turn pages.
- **Outcome / status:** shipped on master, not yet deployed. The preflight-lint half of D7 stays open (`doc/Viva-Exam.md` Known Gaps). Phase B must keep test-drives on the practice alert branch (recorded there).

```

- [ ] **Step 6: `CHANGELOG.md`**

Under `## [Unreleased]` → `### Added`, insert as the **first** bullet (above the "Finish open vivas" bullet):

```markdown
- **Viva test-drives: sit your own viva without polluting the data.** The
  problem edit page shows a **Test-drive** button on viva problems (editors of
  the problem's group and admins). It runs a real interview and grading, but
  the session is flagged as a test-drive: excluded from the problem list,
  scores, contest scoreboards, every Report page, the stat pages, the
  AI-usage report and the API; not counted against the author's daily starts;
  not blocked by the contest-only rule; restartable without limit. Test-drives
  are listed in the Viva Exam card of the edit page and badged on the viva
  session, viva alerts and stuck-turn pages. Other students never see them,
  even when a problem shares transcripts. Adds `submissions.test_drive`
  (migration). (rev <REV1>–<REV3>)
```

- [ ] **Step 7: Verify the docs edits landed**

Run:
```bash
grep -c 'Test-Drive Sessions' doc/Viva-Exam.md          # expect 1
grep -c 'Sit it yourself first' doc/wiki/viva-authoring-guide.md   # expect 1
grep -c 'Test-driving a viva' doc/wiki/instructor-viva-guide.md     # expect 1
grep -c 'Test-drive sessions: authors sit' doc/Viva-History.md      # expect 1
grep -c 'Viva test-drives: sit your own viva' CHANGELOG.md          # expect 1
grep -n '<REV' doc/Viva-Exam.md doc/Viva-History.md CHANGELOG.md    # expect NO output (all placeholders replaced with real rev numbers)
```

- [ ] **Step 8: Commit**

```bash
cat > /tmp/td-task4.txt <<'MSG'
docs: viva test-drive sessions — reference section, authoring + instructor guides, history, changelog

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
test "$(hg log -r . --template '{activebookmark}')" = master || { echo "NOT ON MASTER"; exit 1; }
hg commit -l /tmp/td-task4.txt doc/Viva-Exam.md doc/wiki/viva-authoring-guide.md doc/wiki/instructor-viva-guide.md doc/Viva-History.md CHANGELOG.md
```

---

## Not in this plan (deliberately)

- Merging master into `chula_cp`: the controller does it once after the final review, together with the spec/plan commits.
- The D7 preflight lint.
- A system (browser) test — the integration tests cover the markup; the controller renders a screenshot pass after the final review.
