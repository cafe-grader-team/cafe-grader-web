# Exam Slip Passwords Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin turn off CU-net login for one contest's students until the contest ends, add a no-save Check step to the Import Users page, and restyle that page.

**Architecture:** Master gets a dormant "outside login" seam (three class methods in a concern), a `contests.outside_login_off` column, a "blocked" rule, and one login flow (`User.login_result`) used by both login doors. Chula_cp later plugs CUCAS into the seam in one small commit. The import text gets one parser (`UserImportList`) shared by Create and the new Check.

**Tech Stack:** Rails 8, HAML, simple_form, Stimulus (lazy-loaded from `app/javascript/controllers`), Turbo Streams, Minitest (+ `minitest/mock` stubs), Capybara system tests.

**Spec:** `docs/superpowers/specs/2026-11-21-exam-slip-passwords-design.md` (approved by dae 2026-11-21). Read it before starting; it holds the reasons.

## Global Constraints

- Work in a throwaway clone: `hg clone -u master /home/dae/cafe-grader/web /home/dae/cafe-grader/web-slip-ws`; run everything there. At the very end, `hg push -B master -B chula_cp ../web` (the local main repo). **Never push to GitHub, never deploy** (2026-11-21 is an exam day).
- Commits: Tasks 1–6 on `master` only, gated: `[ "$(hg log -r . -T '{activebookmark}')" = "master" ] && hg commit <explicit files> -m "…"`. Always name the files; never commit `.superpowers/`, `tmp/` or untracked files you didn't create. Task 7 is the one authorized exception (a chula_cp merge plus one Chula-only commit).
- Commit message trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01VNxm1PuQkxzDvP8Nn9makd`.
- No user personal data in code, tests, docs or commit messages: use fixture users (`john`/hello, `james`/morning, `jack`/morning, `mary`/mary (group editor, contest_a editor), `admin`/admin) and invented logins.
- Generic code says **outside login**; text a user sees says `User.outside_login_name` ("CU-net" on chula_cp). Never hard-code "CU-net" on master.
- Exact copy (`#{name}` = `User.outside_login_name`):
  - checkbox label: `Turn off #{name} login for this contest's students until the contest ends`
  - hint lines: `#{name} login is currently ON for the rest of the site.` (or `OFF`) and `Ticked now, it covers this contest's students until <time>.` (time as `%d/%b/%Y %H:%M`, the form's date format)
  - badge: `#{name} off for students`
  - refusal: `This exam uses the password on your seat slip. Your #{name} password will work again after the exam ends.`
  - validation: error on `:outside_login_off`, `needs a Stop time`
  - Check stale note: `The list changed. Press Check again.`
- UI rules from `CLAUDE.md` "Frontend & UI Conventions": `.mi` icons, flat `data:` keys, Flavor B for the hidden Check form, `init-ui-component` around tooltips, `.mb-4` between major cards.
- **Create following users must behave exactly as today.** Task 4's pinning tests guard it.
- CHANGELOG: an `[Unreleased]` bullet in the same commit as each user-facing change, citing the rev (use the rev the commit will get: `hg log -r tip -T '{rev}'` + 1).
- Test commands: `bin/rails test <files>`; system tests `HEADLESS=1 bin/rails test test/system/<file>`; before Task 7 and after it, `bin/rails check`.

## Review Focus

1. **Login typed in a different case** in the import list ("JOHN" for `john`): MySQL matches it case-insensitively, so Check must report the existing user, not a new account (test in Task 5).
2. **Pasted text with Windows line endings and trailing blank lines**: Create already reads CRLF; Check must read it the same way and must not report blank lines as ignored (tests in Tasks 4 and 5).
3. **A student with extra time** stays blocked after Stop until Stop plus their extra time (test in Task 1).
4. **Unticking mid-exam** ends the block at once (test in Task 1).
5. **Check then Create on the same text** must agree: Check's new accounts are exactly the accounts Create makes (parity test in Task 5).

---

### Task 1: Outside-login seam, contest column, and the blocked rule

**Files:**
- Create: `db/migrate/20261121120000_add_outside_login_off_to_contests.rb`
- Modify: `db/schema.rb` (by running the migration)
- Create: `app/models/concerns/outside_login.rb`
- Modify: `app/models/user.rb` (include the concern; add `#outside_login_blocked?`)
- Modify: `app/models/contest_user.rb` (scope)
- Modify: `app/models/contest.rb` (`audited only:` list; `#outside_login_block_ends_at`)
- Test: `test/models/outside_login_test.rb` (new)

**Interfaces:**
- Produces:
  - column `contests.outside_login_off` (boolean, `default: false, null: false`)
  - `User.outside_login_name -> String | nil` (master: `nil`)
  - `User.outside_login_available? -> Boolean` (`outside_login_name.present?`)
  - `User.outside_login_on? -> Boolean` (master: `false`; chula_cp: the site switch)
  - `User.outside_password?(user, password) -> Boolean` (master: `false`; chula_cp: CUCAS)
  - `ContestUser.blocking_outside_login(now = Time.zone.now) -> ActiveRecord::Relation`: rows with role `user`, whose contest has `outside_login_off` true, and where `DATE_ADD(contests.stop, INTERVAL IFNULL(contests_users.extra_time_second, 0) SECOND) > now`. Ignores both `enabled` flags on purpose (spec Part 1).
  - `User#outside_login_blocked?(now = Time.zone.now) -> Boolean` (the scope, for this user, `exists?`)
  - `Contest#outside_login_block_ends_at -> Time | nil`: `stop + (max extra_time_second over role-user rows, or 0)`; `nil` when `stop` is nil.

The three seam methods live in `OutsideLogin` (`ActiveSupport::Concern`, `class_methods do … end`) so chula_cp edits only that file.

- [ ] **Step 1: Write the failing tests** in `test/models/outside_login_test.rb`:

```ruby
test "master has no outside login" do
  skip 'this deployment has an outside login' if User.outside_login_available?   # chula_cp
  assert_nil User.outside_login_name
  assert_not User.outside_login_available?
  assert_not User.outside_login_on?
  assert_not User.outside_password?(users(:john), 'anything')
end

test "a student of a ticked contest is blocked; unticked is not" do
  assert_not users(:james).outside_login_blocked?
  contests(:contest_a).update!(outside_login_off: true)
  assert users(:james).outside_login_blocked?
end

test "an editor of a ticked contest is never blocked" do
  contests(:contest_a).update!(outside_login_off: true)
  assert_not users(:mary).outside_login_blocked?
end

test "the block ends at stop plus that student's extra time" do
  c = contests(:contest_a); c.update!(outside_login_off: true)
  contests_users(:james_in_contest_a).update!(extra_time_second: 600)
  assert users(:james).outside_login_blocked?(c.stop + 1.second)
  assert_not users(:james).outside_login_blocked?(c.stop + 601.seconds)
  assert_not users(:jack).outside_login_blocked?(c.stop + 1.second)
end

test "disabled contest and disabled row still block" do
  contests(:contest_a).update!(outside_login_off: true, enabled: false)
  contests_users(:james_in_contest_a).update!(enabled: false)
  assert users(:james).outside_login_blocked?
end

test "one ticked contest among several is enough" do
  contests(:contest_b).update!(outside_login_off: true)   # jack is in contest_a (unticked) and contest_b
  assert users(:jack).outside_login_blocked?
end

test "unticking mid-exam ends the block at once" do
  c = contests(:contest_a); c.update!(outside_login_off: true)
  c.update!(outside_login_off: false)
  assert_not users(:james).outside_login_blocked?
end

test "block end time is stop plus the longest student extra time" do
  c = contests(:contest_a)
  contests_users(:james_in_contest_a).update!(extra_time_second: 600)
  assert_equal c.stop + 600.seconds, c.outside_login_block_ends_at
  assert_nil Contest.new(name: 'nostop').outside_login_block_ends_at
end

test "ticking is audited" do
  assert_difference -> { AuditLog.where(auditable: contests(:contest_a)).count }, 1 do
    contests(:contest_a).update!(outside_login_off: true)
  end
  assert AuditLog.where(auditable: contests(:contest_a)).last.object_changes.key?('outside_login_off')
end
```

- [ ] **Step 2: Run, expect failure** — `bin/rails test test/models/outside_login_test.rb` → errors (unknown attribute / undefined method).
- [ ] **Step 3: Write the migration** (`add_column :contests, :outside_login_off, :boolean, default: false, null: false`), run `bin/rails db:migrate`, confirm `db/schema.rb` gains the column and version `2026_11_21_120000`.
- [ ] **Step 4: Implement** the concern, the scope, `User#outside_login_blocked?`, `Contest#outside_login_block_ends_at`, and add `outside_login_off` to Contest's `audited only:` list.
- [ ] **Step 5: Run, expect pass** — `bin/rails test test/models/outside_login_test.rb test/models/contest_test.rb test/models/user_test.rb`.
- [ ] **Step 6: Commit** `db/migrate/20261121120000_add_outside_login_off_to_contests.rb db/schema.rb app/models/concerns/outside_login.rb app/models/user.rb app/models/contest_user.rb app/models/contest.rb test/models/outside_login_test.rb` — message `outside login: contest setting column and the blocked rule (dormant on master)`. No CHANGELOG yet (nothing visible).

---

### Task 2: One login flow for both doors

**Files:**
- Modify: `app/models/user.rb` (`LoginResult`, `.login_result`, `.authenticate`, `.outside_login_refused_message`)
- Modify: `app/controllers/concerns/login_throttling.rb` (`record_refused_login!`)
- Modify: `app/controllers/login_controller.rb` (`#login`)
- Modify: `app/controllers/api/v1/auth_controller.rb` (`#login`)
- Modify: `test/test_helper.rb` (`OutsideLoginHelper`)
- Test: `test/models/outside_login_test.rb` (add), `test/integration/outside_login_refusal_test.rb` (new)

**Interfaces:**
- Consumes: Task 1's seam methods and `User#outside_login_blocked?`.
- Produces:
  - `User::LoginResult = Data.define(:user, :refusal)`; `refusal` is `nil` or `:slip_password_required`
  - `User.login_result(login, password) -> User::LoginResult`
  - `User.authenticate(login, password) -> User | nil` (now `login_result(login, password).user`; contract unchanged)
  - `User.outside_login_refused_message -> String` (exact copy in Global Constraints)
  - `LoginThrottling#record_refused_login!`: writes the same failed `Login` row as `record_login_failure!` but touches no cache counter. Extract the shared `Login.create(...)` into one private method.
  - test helper `with_outside_login(accepts: 'cunet-pass', name: 'CU-net') { … }`: stubs `User.outside_login_name` → `name`, `User.outside_login_on?` → `true`, `User.outside_password?` → `->(_user, pw) { pw == accepts }` (needs `require "minitest/mock"`). Also `without_outside_login { … }`: stubs `outside_login_name` → `nil` and `outside_login_on?` → `false`, so "no outside login" tests also pass on chula_cp. Put both in one `OutsideLoginHelper` module, included in `ActiveSupport::TestCase`.

`login_result` order (this is the spec's behaviour table; keep it in this order):
1. no user with that login → `(nil, nil)`
2. local password matches (`authenticated?`) → `(user, nil)`, blocked or not
3. `!outside_login_on?` → `(nil, nil)`, and `outside_password?` is never called
4. `user.outside_login_blocked?` → `(nil, :slip_password_required)` if `outside_password?(user, password)`, else `(nil, nil)`; the local password is never touched
5. `outside_password?(user, password)` → set `user.password = password`, `user.save`, `(user, nil)` (today's chula_cp caching, unchanged, including that it doesn't check `activated`)
6. otherwise `(nil, nil)`

Controllers: call `User.login_result` first. On a refusal, call `record_refused_login!` and answer with the refusal message: the web door redirects to `login_main_path` with `alert:`; the API returns 401 `{ error: <message> }`. With no refusal and no user, keep today's path. The web door still tries `@@authenticators`, then `record_login_failure!`.

- [ ] **Step 1: Write the failing model tests** (add to `test/models/outside_login_test.rb`):

```ruby
test "the slip password always works, even when blocked" do
  contests(:contest_a).update!(outside_login_off: true)
  with_outside_login { assert_equal users(:james), User.login_result('james', 'morning').user }
end

test "site switch off never asks the outside service" do
  User.stub(:outside_password?, ->(*) { flunk 'must not call the outside service' }) do
    r = User.login_result('john', 'wrong')
    assert_nil r.user; assert_nil r.refusal
  end
end

test "switch on, not blocked: outside password logs in and becomes the local one" do
  with_outside_login do
    assert_equal users(:john), User.login_result('john', 'cunet-pass').user
  end
  assert users(:john).reload.authenticated?('cunet-pass')
end

test "switch on, blocked, right outside password: refused and the slip password survives" do
  contests(:contest_a).update!(outside_login_off: true)
  with_outside_login do
    r = User.login_result('james', 'cunet-pass')
    assert_nil r.user
    assert_equal :slip_password_required, r.refusal
  end
  assert users(:james).reload.authenticated?('morning')
end

test "switch on, blocked, wrong outside password: plain failure" do
  contests(:contest_a).update!(outside_login_off: true)
  with_outside_login do
    r = User.login_result('james', 'nope')
    assert_nil r.user; assert_nil r.refusal
  end
end

test "unknown login and the authenticate wrapper" do
  assert_nil User.login_result('no_such_login', 'x').user
  assert_equal users(:john), User.authenticate('john', 'hello')
end

test "refusal message names the outside login" do
  with_outside_login do
    assert_equal "This exam uses the password on your seat slip. Your CU-net password will work again after the exam ends.",
                 User.outside_login_refused_message
  end
end
```

- [ ] **Step 2: Write the failing integration tests** in `test/integration/outside_login_refusal_test.rb`. Use the `LoginThrottlingTest` setup (swap in `ActiveSupport::Cache::MemoryStore`, restore in teardown) and read counters with `Rails.cache.read(LoginThrottling.account_key('james'))` / `LoginThrottling.ip_key('127.0.0.1')`:
  - `web: blocked student with the right CU-net password is refused, told to use the slip, and not counted`: `contest_a` ticked; inside `with_outside_login`, `post login_login_path, params: {login: 'james', password: 'cunet-pass'}` → `assert_redirected_to login_main_path`; `assert_equal User.outside_login_refused_message, flash[:alert]` (call it inside the block); `assert_nil session[:user_id]`; `Login.where(success: false, attempted_login: 'james').count` +1; both counters `.to_i == 0`.
  - `web: blocked student with a wrong password is counted as today`: same, password `'nope'` → `flash[:alert] == 'Wrong password'`, account counter `== 1`.
  - `web: blocked student with the slip password gets in` → `assert_redirected_to list_main_path`.
  - `api: refusal is a 401 with the message and is not counted`: `post "/api/v1/auth/login", params: {login: 'james', password: 'cunet-pass'}, as: :json` → `assert_response :unauthorized`; `response.parsed_body['error'] == User.outside_login_refused_message`; counters 0; `Login` row +1.
- [ ] **Step 3: Run, expect failure** — `bin/rails test test/models/outside_login_test.rb test/integration/outside_login_refusal_test.rb`.
- [ ] **Step 4: Implement** per the Interfaces block.
- [ ] **Step 5: Run, expect pass**, plus the neighbours: `bin/rails test test/models/outside_login_test.rb test/integration/outside_login_refusal_test.rb test/integration/login_throttling_test.rb test/integration/login_test.rb test/models/user_test.rb` and `bundle exec rspec spec/requests/api/v1/auth_spec.rb`. The swagger file is unchanged (the 401 is already documented); confirm with `bin/rails swagger:verify`.
- [ ] **Step 6: Commit** the six files above plus the new test file — message `outside login: one login flow for web and API; a blocked student's outside password is refused and not counted`. No CHANGELOG yet (still dormant on master).

---

### Task 3: Contest setting in the UI (admin-only), clone, badge

**Files:**
- Modify: `app/models/contest.rb` (validation)
- Modify: `app/controllers/contests_controller.rb` (`contests_params`, `clone`)
- Modify: `app/views/contests/_form.html.haml` (checkbox after `:enabled`)
- Modify: `app/views/contests/show.html.haml` (badge beside the "Manage" badge in the title row)
- Modify: `CHANGELOG.md` (`### Added`), `doc/backlog.md` (one item, below)
- Test: `test/models/contest_test.rb`, `test/integration/contests_controller_test.rb`

**Interfaces:**
- Consumes: `contests.outside_login_off`, `User.outside_login_available?`, `User.outside_login_name`, `User.outside_login_on?`, `Contest#outside_login_block_ends_at`.
- Produces: nothing new for later tasks.

Rules:
- `contests_params` (the non-finalized branch) permits `:outside_login_off` only when `@current_user.admin? && User.outside_login_available?`. The finalized branch is unchanged.
- The form shows the checkbox only when `User.outside_login_available?`. It is `disabled:` when the contest is finalized or the viewer is not an admin. Hint: the two lines from Global Constraints; the second line only when `outside_login_block_ends_at` is present.
- Validation `outside_login_off_needs_stop`: ticked with `stop` nil → `errors.add(:outside_login_off, 'needs a Stop time')`.
- `clone` passes `outside_login_off: @contest.outside_login_off` to `Contest.new`.
- Badge (only when available and ticked): a rounded-pill warning-subtle badge with the badge copy and a tooltip `Until <time>` (`data: {bs_toggle: 'tooltip'}`, `title:`); the page wrapper already carries `init-ui-component`.

- [ ] **Step 1: Write the failing tests.**
  - Model, `test/models/contest_test.rb`: `ticking without a Stop time is refused`: `c = contests(:contest_a); c.stop = nil; c.outside_login_off = true; assert_not c.valid?; assert_includes c.errors[:outside_login_off], 'needs a Stop time'`.
  - Integration, `test/integration/contests_controller_test.rb`:
    - `admin can tick the outside-login box where an outside login exists`: `sign_in_as('admin','admin')`; inside `with_outside_login`, `patch contest_path(contests(:contest_a)), params: {contest: {outside_login_off: '1'}}` → `contests(:contest_a).reload.outside_login_off` true.
    - `a group editor cannot tick it`: `sign_in_as('mary','mary')`, same patch inside `with_outside_login` → stays false.
    - `without an outside login the box is ignored and hidden`: admin patch `'1'` inside `without_outside_login` → stays false; `get edit_contest_path(contests(:contest_a))` → body has no `login for this contest's students`.
    - `edit page shows the box and the site switch state`: admin, inside `with_outside_login` → body includes `Turn off CU-net login for this contest&#39;s students until the contest ends` (HTML-escaped apostrophe; or assert on `login for this contest` plus `is currently ON for the rest of the site`).
    - `clone keeps the setting`: tick `contest_a`, `get clone_contest_path(contests(:contest_a))` as admin → `Contest.order(:id).last.outside_login_off` true.
    - `show page badge`: tick `contest_a`; admin `get contest_path(...)` inside `with_outside_login` → includes `CU-net off for students`; inside `without_outside_login` → does not.
- [ ] **Step 2: Run, expect failure** — `bin/rails test test/models/contest_test.rb test/integration/contests_controller_test.rb`.
- [ ] **Step 3: Implement** the rules above.
- [ ] **Step 4: Run, expect pass** (same command), then `HEADLESS=1 bin/rails test test/system/contests_test.rb`.
- [ ] **Step 5: Docs.**
  - CHANGELOG `### Added`: "**Turn off an outside login (CU-net) for one contest's students.** An admin ticks the box on the contest's edit page. Until the contest ends (plus each student's extra time), those students can log in only with the password the admin imported. A CU-net login can't replace that password, and a correct CU-net password typed by mistake shows a 'use the password on your seat slip' message and doesn't count toward the login lockout. Everyone else keeps CU-net; the site-wide switch is unchanged. Hidden on deployments without an outside login. (revs <Task 1>–<this>)"
  - `doc/backlog.md`: "Contest edit form shows Pre/Post contest seconds but `ContestsController#contests_params` doesn't permit them, so edits to them are silently dropped (found 2026-11-21)."
- [ ] **Step 6: Commit** the seven files above — message `contest: admin-only "turn off outside login" box, clone keeps it, badge on the manage page`.

---

### Task 4: One parser for the import text (no behaviour change)

**Files:**
- Create: `app/models/user_import_list.rb`
- Modify: `app/models/user.rb` (`self.create_from_list` iterates parsed rows)
- Test: `test/models/user_test.rb` (pinning tests), `test/models/user_import_list_test.rb` (new)

**Interfaces:**
- Produces:
  - `UserImportList.new(text)`; `#rows -> Array<UserImportList::Row>`; `#ignored_line_nos -> Array<Integer>`
  - `UserImportList::Row = Data.define(:line_no, :login, :full_name, :password, :password_mode, :user_alias, :remark)`
  - `password_mode` is `:given` (non-empty third field; `password` holds it), `:keep` (third field present but empty; `password` nil), or `:random` (exactly two fields; `password` nil)
  - `remark` is `nil` when there is no fifth field (meaning "don't touch")

Parsing is today's code, moved:
- `text.split("\n")`, then each line `line.chomp.split(',', 1000)`; `line_no` is the 1-based index.
- Fewer than two fields → not a row; its `line_no` goes to `ignored_line_nos` only if `line.strip` is non-empty.
- `login = items[0]`, `full_name = items[1]`, both unstripped, as today.
- password: `items[2].chomp(" ")` decides `:given` / `:keep`.
- `user_alias`: `items[3].chomp(" ")` when there are four or more fields and it is non-empty, else `login`.
- `remark`: `items[4].strip` when there are five or more fields.

`create_from_list` keeps its return hash and its effects:
- existing user: `full_name` always; `remark` unless nil; `password` for `:given`; `random_password` for `:random`; nothing for `:keep`; alias never.
- new user: `password || random_password`; `alias: user_alias`; `remark: remark || ''`.

- [ ] **Step 1: Write pinning tests** in `test/models/user_test.rb`. They pin today's behaviour and **must pass on the old code** (run them before touching `create_from_list`):
  - `two fields give an existing user a random password`: `User.create_from_list("john,John")` → `assert_not users(:john).reload.authenticated?('hello')`.
  - `an empty password field keeps the password`: `"john,John Kept,"` → `authenticated?('hello')`, `full_name == 'John Kept'`.
  - `alias only applies to new accounts`: `"newalias1,New A,pw,ali\nnewalias2,New B,pw,\njohn,John,pw,other"` → `newalias1.alias == 'ali'`, `newalias2.alias == 'newalias2'`, john's alias unchanged.
  - `a fifth field sets the remark, even blank; four fields leave it`: `users(:john).update!(remark: 'r0')`; `"john,John,pw,,"` → remark `''`; reset to `'r0'`; `"john,John,pw,"` → remark `'r0'`.
  - `short and blank lines are skipped without error`: `"justlogin\n\n   \njohn,John,pw"` → `error_logins` empty, `User.find_by_login('justlogin')` nil, 1 updated.
  - `CRLF line endings`: `"john,John CR,pw\r\n"` → `full_name == 'John CR'`, `authenticated?('pw')`.
  - `the last of duplicate rows wins`: `"john,A,p1\njohn,B,p2"` → `full_name == 'B'`, `authenticated?('p2')`.
- [ ] **Step 2: Run them on the old code, expect PASS** — `bin/rails test test/models/user_test.rb`. A failure here means the test is wrong about today's behaviour: fix the test, never the code.
- [ ] **Step 3: Write the failing parser tests** in `test/models/user_import_list_test.rb`:
  - modes: `"a,A\nb,B,\nc,C,pw"` → `rows.map(&:password_mode) == [:random, :keep, :given]`, `rows.last.password == 'pw'`.
  - line numbers and ignored lines: `"a,A\nlonely\n\n  \nb,B"` → `rows.map(&:line_no) == [1, 5]`, `ignored_line_nos == [2]`.
  - CRLF: `"a,A,pw\r\n"` → `rows.first.password == 'pw'`, `full_name == 'A'`.
  - remark nil vs blank: `"a,A,pw,al"` → `remark` nil; `"a,A,pw,al,"` → `remark == ''`.
- [ ] **Step 4: Run, expect failure** (`NameError: uninitialized constant UserImportList`).
- [ ] **Step 5: Implement** `UserImportList` and switch `create_from_list` to it.
- [ ] **Step 6: Run, expect pass** — `bin/rails test test/models/user_test.rb test/models/user_import_list_test.rb test/integration/user_admin_controller_test.rb`.
- [ ] **Step 7: Commit** the four files — message `user import: one parser for the import text (behaviour unchanged, pinned by tests)`. No CHANGELOG (internal).

---

### Task 5: The Check step

**Files:**
- Modify: `app/models/user_import_list.rb` (`Check`, `#check`)
- Modify: `config/routes.rb` (`post 'check_list'` in the `user_admin` collection, next to `create_from_list`)
- Modify: `app/controllers/user_admin_controller.rb` (`#check_list`)
- Create: `app/views/user_admin/_import_check.html.haml`
- Create: `app/javascript/controllers/user_admin/import_controller.js` (Stimulus id `user-admin--import`)
- Modify: `app/views/user_admin/new_list.html.haml` (hooks only; Task 6 restyles)
- Modify: `CHANGELOG.md` (`### Added`)
- Test: `test/models/user_import_list_test.rb`, `test/integration/user_admin_controller_test.rb`, `test/system/user_import_check_test.rb` (new)

**Interfaces:**
- Consumes: Task 4's `UserImportList`, Task 1's `ContestUser.blocking_outside_login` and `User.outside_login_available?` / `.outside_login_name`.
- Produces:
  - `UserImportList::Check = Data.define(:row_count, :new_password, :random_password, :keep_password, :new_accounts, :duplicates, :name_changes, :remark_changes, :ignored_line_nos, :not_covered)`. Each list is `Array<String>` of logins as typed in that login's last row; `ignored_line_nos` is `Array<Integer>`; `not_covered` is `nil` when `!User.outside_login_available?`.
  - `UserImportList#check(now: Time.zone.now) -> UserImportList::Check`
  - `POST /user_admin/check_list` (`check_list_user_admin_index_path`): params `user_list`, `add_to_group`, `group_id`; responds with `turbo_stream.update('import-check', partial: 'user_admin/import_check', locals: {check:, group_name:})`. `group_name` is the group's name when `add_to_group == '1'`, else nil. Admin-only through the controller's existing `before_action`.

Passwords: `User` validates passwords at 4–50 characters, so any test text that reaches Create uses passwords of 4+ characters (Ruling R3).

Check rules:
- Key logins by `login.downcase` (MySQL compares logins case-insensitively); the last row per key wins. `duplicates` = keys with more than one row.
- Load existing users in one query.
- Existing user: by `password_mode` → `new_password` / `random_password` / `keep_password`; `name_changes` when `full_name` differs; `remark_changes` when `remark` is non-nil and differs from `user.remark.to_s`.
- Missing user → `new_accounts`.
- `not_covered` (only when available): logins that get a new password (existing `:given`/`:random`, and every new account) whose user id is not in `ContestUser.blocking_outside_login(now).where(user_id: ids).distinct.pluck(:user_id)`.
- Check saves nothing and writes no audit row.

Panel (`_import_check`): a "Check result" heading with `Checked at HH:MM`. One line per non-empty category, in the spec's order, each with a warning or info icon (spec Part 2 marks which is which). Each line shows up to 10 logins (escaped, comma-separated), with a `<details>` "show all N" when there are more. The group line comes last when `group_name` is present. When `row_count` is 0: `No user lines found.` Line copy, `n`-pluralized with `pluralize`:
`N existing users get a new password` · `N existing users get a random password (row has only login and name)` · `N existing users keep their password (empty password field)` · `N new accounts will be created; on an exam import this usually means a mistyped login` · `N logins are listed more than once (the last row wins)` · `N existing users' names will change` · `N existing users' remarks will change` · `N lines will be ignored (fewer than two fields): lines 2, 7` · `N users get a new password but are not yet covered by a contest with #{name} login turned off; a #{name} login before they are covered replaces the new password` · `These users will also be added to group #{group_name}`.

Page hooks (Flavor B): wrap the page in `data-controller="user-admin--import"`. A hidden `form_with url: check_list_user_admin_index_path, data: {turbo: true}` carries hidden `user_list`, `add_to_group`, `group_id`. Its targets: `checkForm`, `checkList`, `checkAddToGroup`, `checkGroupId`; the visible inputs are targets `list`, `addToGroup`, `groupId`. A `type="button"` **Check** button beside **Create following users** fires `user-admin--import#check`: it copies the values (checkbox → `'1'`/`'0'`) and calls `requestSubmit()`. An empty `#import-check` container (target `panel`) receives the stream. Textarea `input` → `user-admin--import#markStale`, which shows the stale note (target `stale`, `d-none` until then) only when the panel has content. The stream replacing the panel hides the note again. The visible form keeps posting to `create_from_list` exactly as today.

- [ ] **Step 1: Write the failing model tests** (add to `test/models/user_import_list_test.rb`):

```ruby
test "check sorts rows into categories" do
  users(:john).update!(remark: 'r0')
  c = without_outside_login { UserImportList.new("john,john,newpw,,r1\njames,James Renamed\njack,Jack,\nnewbie1,New Bie,pw\nlonely").check }
  assert_equal ['john'], c.new_password
  assert_equal ['james'], c.random_password
  assert_equal ['jack'], c.keep_password
  assert_equal ['newbie1'], c.new_accounts
  assert_equal ['james'], c.name_changes
  assert_equal ['john'], c.remark_changes
  assert_equal [5], c.ignored_line_nos
  assert_nil c.not_covered            # no outside login
  assert_equal 4, c.row_count
end

test "check matches logins case-insensitively and reports duplicates" do
  c = UserImportList.new("JOHN,john,pw\njohn,john,pw2").check
  assert_equal [], c.new_accounts
  assert_equal ['john'], c.duplicates
  assert_equal ['john'], c.new_password
end

test "blank lines and CRLF are not reported as ignored" do
  c = UserImportList.new("john,john,pw\r\n\r\n   \r\n").check
  assert_equal [], c.ignored_line_nos
  assert_equal ['john'], c.new_password
end

test "not covered lists new passwords outside a ticked contest" do
  contests(:contest_a).update!(outside_login_off: true)
  with_outside_login do
    c = UserImportList.new("james,james,pw\njohn,john,pw\nnewbie2,N,pw\njack,jack,").check
    assert_equal ['john', 'newbie2'], c.not_covered.sort   # james blocked; jack keeps his password
  end
end

test "check saves nothing" do
  assert_no_difference -> { User.count } do
    assert_no_difference -> { AuditLog.count } do
      UserImportList.new("newbie3,N,pw\njohn,Renamed,pw").check
    end
  end
  assert users(:john).reload.authenticated?('hello')
end

test "check and create agree on new accounts" do
  text = "john,john,pass\nnewbie4,N,pass\nNEWBIE5,M,\nnewbie4,N2,pass2"
  check = UserImportList.new(text).check
  created = User.create_from_list(text)[:created_users].pluck(:login)
  assert_equal check.new_accounts.map(&:downcase).sort, created.map(&:downcase).sort
end
```

- [ ] **Step 2: Write the failing integration tests** (add to `test/integration/user_admin_controller_test.rb`):
  - `check_list renders the result panel and saves nothing`: admin; `assert_no_difference -> { User.count }` around `post check_list_user_admin_index_path, params: {user_list: "newbie6,N,pw"}, headers: {'Accept' => 'text/vnd.turbo-stream.html'}`; `assert_equal 'text/vnd.turbo-stream.html', response.media_type`; body includes `import-check` and `1 new account`.
  - `check_list names the group when asked`: params add `add_to_group: '1', group_id: groups(:group_a).id` → body includes `added to group`.
  - `non-admin cannot check`: `sign_in_as('john','hello')`, same post → `assert_redirected_to list_main_path`.
- [ ] **Step 3: Write the failing system test** `test/system/user_import_check_test.rb` (with the local `login` helper copied from `test/system/users_test.rb`):
  - `Check shows the result without saving; editing marks it stale; Create still works`: login admin; `visit new_list_user_admin_index_path`; fill the textarea (`find('textarea[name="user_list"]').set("john,john,newpw\nnewbie7,New Bie,pass")`); `click_on 'Check'`; `assert_text '1 new account', wait: 10`; `assert users(:john).reload.authenticated?('hello')`; `find('textarea[name="user_list"]').set("john,john,newpw\nnewbie7,New Bie,pass\nnewbie8,X,pass")` (typing fires `input`); `assert_text 'The list changed. Press Check again.'`; `click_on 'Create following users'`; `assert_text 'were created successfully', wait: 10`; `assert User.find_by_login('newbie8')`.
- [ ] **Step 4: Run, expect failure** — `bin/rails test test/models/user_import_list_test.rb test/integration/user_admin_controller_test.rb` and `HEADLESS=1 bin/rails test test/system/user_import_check_test.rb`.
- [ ] **Step 5: Implement** the rules, the route, the action, the partial, the Stimulus controller and the page hooks.
- [ ] **Step 6: Run, expect pass** (same commands, plus `HEADLESS=1 bin/rails test test/system/users_test.rb`).
- [ ] **Step 7: CHANGELOG** `### Added`: "**Check before importing users.** The Import Users page has a Check button beside Create following users. It shows, without saving anything, what the import would do: who gets a new or random password, which logins would become new accounts (usually a typo on an exam import), duplicates, name and remark changes, ignored lines, and, where an outside login exists, who isn't yet covered by a contest that turns it off. Create works as before. (rev <this>)"
- [ ] **Step 8: Commit** the files above plus the new tests — message `user import: Check shows what an import would do without saving`.

---

### Task 6: Restyle the Import Users page (screenshots before commit)

**Files:**
- Modify: `app/views/user_admin/new_list.html.haml`
- Modify: `CHANGELOG.md` (`### Changed`)
- Scratch (not committed): a throwaway system test that saves screenshots, under the session scratchpad; output PNGs and an `index.html` in `tmp/import-restyle-2026-11-21/` (hg-ignored).

**Interfaces:**
- Consumes: Task 5's Stimulus targets, hidden form and `#import-check` panel. Keep every target and action name.

Layout (spec Part 3):
- Page header: the pattern of `app/views/user_admin/index.html.haml` (small uppercase "Management" over an `h2`), titled `Import Users`.
- **Left `.col-md-6`:** the textarea (unchanged name `user_list`, height `30rem`); one row of buttons: **Check** (`btn btn-outline-primary`) then **Create following users** (`btn btn-success`); the group checkbox and select.
- **Right `.col-md-6`:** `#import-check` first, then the instruction card `.card.border-0.shadow-sm.border-start.border-4.border-info.mb-4` with a `lightbulb` icon and the heading "Import Instructions" (copy the `#tab-add-users` markup in `app/views/contests/show.html.haml`).
- Card body (`.text-secondary.small`):
  - the format line `user_id,name[,passwd[,alias[,remark]]]` in the `.bg-light.p-2.rounded.font-monospace.small` box;
  - bullets: `One user per line. A login that already exists is updated; a new login creates an account.` · `passwd, alias and remark are optional.` · `A missing passwd sets a random password. An empty passwd (a trailing comma) keeps the current one; a new account still gets a random one.` · `alias is used only when an account is created.`;
  - the two existing examples, with their explanations, unchanged;
  - a "For an exam import" block: `Press Check first.` and, only when `User.outside_login_available?`, `If the students already have accounts, add them to the contest (with #{name} login turned off) before importing passwords: a #{name} login in between replaces the new password. New accounts can't be added to a contest yet, so import them first and add them straight after.`
- No yellow `bg-warning-subtle` card anywhere on the page.

- [ ] **Step 1: Before screenshot** — with the Task 5 page as it is, write a throwaway system test in the scratchpad that logs in as admin, visits `new_list_user_admin_index_path`, and saves `tmp/import-restyle-2026-11-21/before.png` (`page.save_screenshot`, window 1400×1400). Also save `before_check.png` after pressing Check on `"john,john,newpw\nnewbie9,N,pw\nlonely"`.
- [ ] **Step 2: Restyle** the view per the layout above.
- [ ] **Step 3: After screenshots** — the same test saves `after.png` and `after_check.png`; build `tmp/import-restyle-2026-11-21/index.html` showing before/after side by side.
- [ ] **Step 4: Run tests** — `bin/rails test test/integration/user_admin_controller_test.rb` and `HEADLESS=1 bin/rails test test/system/user_import_check_test.rb test/system/users_test.rb`. Expect pass.
- [ ] **Step 5: Add the CHANGELOG `### Changed` bullet** but **do not commit**: "**Import Users page restyled** to match the contest Import tab: the instructions are a side card instead of a yellow wall of text, and the page says what to do for an exam import. (rev <this>)". Report the screenshot page path. The controller session shows it to dae and commits `app/views/user_admin/new_list.html.haml CHANGELOG.md` only after dae approves (spec Part 3), with message `user import: restyle the Import Users page`.

---

### Task 7: chula_cp: merge master, plug CUCAS into the seam

**Files (on chula_cp):**
- Merge commit: resolve `app/models/user.rb`
- Modify: `app/models/concerns/outside_login.rb`
- Test: `test/models/outside_login_chula_test.rb` (new, chula_cp only)

**Interfaces:**
- Consumes: Task 1's `OutsideLogin` (three class methods) and Task 2's `User.login_result`.
- Produces (chula_cp only): `User.outside_login_name == 'CU-net'`; `User.outside_login_on? == (GraderConfiguration.get('chula.allow_cu_net_password') == true)`; `User.outside_password?(user, password) == user.authenticated_by_cucas?(password)`.

Run this right after Task 5. Task 6 runs after it: the restyle is committed only once dae approves its screenshots (spec Part 3), and it reaches chula_cp in the next batch merge.

- [ ] **Step 1: Merge** — `hg update chula_cp && hg merge master`. Expect a conflict in `app/models/user.rb`'s `self.authenticate`. Resolve by hand:
  - keep master's `self.authenticate` (the one-line wrapper) and `login_result`;
  - drop chula_cp's CU-net branch from `authenticate`;
  - **keep** chula_cp's `authenticated_by_cucas?` method.

  Never resolve the whole file with `:other` or `:local`. Resolve any other conflict by taking master's side, unless the file is a chula_cp-only one listed in `CLAUDE.md` (e.g. `config/llm.yml`); there, keep chula_cp's. `hg resolve -m <file>`, then `hg commit -m "merge master: CU-net off per contest (seam), user import Check step; contest reorder fixes (2300–<last master rev>)"`. The merge alone leaves CU-net login off on chula_cp until Step 3. Never push or deploy between the two commits.
- [ ] **Step 2: Write the failing test** `test/models/outside_login_chula_test.rb`:

```ruby
test "CU-net is chula_cp's outside login" do
  assert_equal 'CU-net', User.outside_login_name
end

test "the site switch drives outside_login_on?" do
  GraderConfiguration.where(key: 'chula.allow_cu_net_password').delete_all
  GraderConfiguration.create!(key: 'chula.allow_cu_net_password', value_type: 'boolean', value: 'true')
  reset_grader_config_cache
  assert User.outside_login_on?
  GraderConfiguration.where(key: 'chula.allow_cu_net_password').update_all(value: 'false')
  reset_grader_config_cache
  assert_not User.outside_login_on?
end

test "outside_password? asks CUCAS" do
  u = users(:john)
  u.stub(:authenticated_by_cucas?, ->(pw) { pw == 'cu-pass' }) do
    assert User.outside_password?(u, 'cu-pass')
    assert_not User.outside_password?(u, 'other')
  end
end
```

  Run → expect failure (`nil` name).
- [ ] **Step 3: Implement** the three overrides in `app/models/concerns/outside_login.rb`. Run `bin/rails test test/models/outside_login_chula_test.rb test/models/outside_login_test.rb test/integration/outside_login_refusal_test.rb test/integration/contests_controller_test.rb test/models/user_import_list_test.rb`. Expect pass, with "master has no outside login" skipped by its own guard. Master's tests use `with_outside_login` / `without_outside_login`, so they need no chula_cp edits. If one does fail only on chula_cp, fix it on master and merge again; don't patch it on chula_cp.
- [ ] **Step 4: Full suite on chula_cp** — `bin/rails check` → 0 failures.
- [ ] **Step 5: Commit** (gate on `chula_cp`): `[ "$(hg log -r . -T '{activebookmark}')" = "chula_cp" ] && hg commit app/models/concerns/outside_login.rb test/models/outside_login_chula_test.rb -m "chula_cp: CU-net is the outside login (CUCAS behind the master seam)"`.
- [ ] **Step 6: Back to master** — `hg update master && bin/rails check` (0 failures). Report the master and chula_cp revs. The push to the local main repo (`hg push -B master -B chula_cp ../web`) happens after Task 6 and the final review. No GitHub push, no deploy.
