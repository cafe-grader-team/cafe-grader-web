# Changelog

All notable changes to this project are recorded here. Format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `[Unreleased]` section at the top accumulates changes between releases.
When a release is cut: rename it to `[X.Y.Z] — YYYY-MM-DD`, bump
`APP_VERSION`, and (optionally) tag the commit in hg/git.

## [Unreleased]

### Added
- **`bin/rails engine:langcheck` — does each language grade on this host?**
  It compiles and runs a small built-in program (read two numbers, print the
  sum) for C++, C, Python, Ruby, Java, Haskell, Rust, Go, Pascal and PHP in the
  real sandbox, with the same compiler classes and isolate options as real
  grading, and prints one line per language: `PASS`, `FAIL` with the phase and
  the compiler's first lines, or `not configured` when `worker.yml` has no
  compiler path for it. It needs no problem and no submission and touches no
  student data. `ONLY=java,cpp` limits it, `BOX=` picks the isolate box
  (default 99), `SKIP_WEB_ONLY=1` skips a host with no grader boxes. Exit 1 on
  any `FAIL`. (rev 2278)
- **Per-host isolate options in `config/worker.yml`, written by
  `bin/rails engine:detect`.** A new optional section, `isolate_options:`
  with one line per language, is added after the built-in options for both the
  compile and the run sandbox. `engine:detect` works out what the host needs
  and prints it; `engine:detect WRITE=1` writes it into `worker.yml` (only that
  line changes) and the graders use it after a restart. Graders never detect
  anything themselves: what a box uses is the line in the file, and each
  grader logs it once at start. `engine:langcheck` also reports when the line
  no longer matches the host, for example after a JDK upgrade. (rev 2278)

### Fixed
- **Java submissions fail to compile with `InternalError: Error loading
  java.security file` on Debian/Ubuntu judge hosts.** The OS package keeps the
  JDK's configuration in `/etc/java-<N>-openjdk`, which the sandbox did not
  mount, so `javac` died before reading the source; on cp-grader no Java
  submission was graded from 2025-08-20 on. **Each judge host needs one manual
  step after this deploy:** `bin/rails engine:detect WRITE=1`, restart the
  graders, then `bin/rails engine:langcheck ONLY=java`. Submissions that
  failed this way are not regraded automatically. (rev 2278)
- **Pascal submissions never compiled.** Two faults. The compiler class read
  `compiler: pascal:` while `worker.yml` defines `compiler: pas:`, so the
  command started with `-O1` (`execve("-O1"): No such file or directory`; rev
  2278). Behind that, `fpc` could not find its standard units inside the
  sandbox (`Can't find unit system used by Program`), because it learns the
  unit directory from `/etc/fpc.cfg`, which the sandbox does not show and,
  being a single file, cannot be mounted. The directory is now passed as an
  `-Fu` flag from a new per-host `compiler_options: pas:` line in
  `worker.yml`, which `bin/rails engine:detect WRITE=1` writes next to the
  Java line; `engine:langcheck` reports it when it goes stale after an fpc
  upgrade. Same manual step per judge host as for Java. (rev 2279)
- **`worker.yml.SAMPLE` had no `compiler: php:` line**, so on a host built
  from it every PHP submission was a compilation error with an empty message.
  Existing hosts: add `php: <%= `which php`.strip %>` under `compiler:` in
  `config/worker.yml` if PHP should work there. (rev 2278)

### Changed
- **AI assist on Claude through the AI gateway costs about half as much
  during exams.** Each request now has a fixed line, "End of the problem
  material. The student's work follows.", between the problem material (the
  `codey-*` prompt tags, the statement PDF, the manager files) and the
  student's work. On gateway requests that line carries a prompt-cache
  marker: Claude keeps the problem material for 5 minutes, and the next
  request on the same problem pays a tenth of the input price for it.
  Measured through the Chula AI Gateway on a Quiz 2 problem, the material is
  82% of the input and the same request cost $0.126 without the marker and
  $0.054 with it. The request that stores the material pays 25% extra on it,
  so a problem nobody asks about for 5 minutes pays that again. In Quiz 2, 94%
  of Opus requests came within 5 minutes of the previous one on the same
  problem. Answers do not change and are about 1 second faster out of a
  typical 22. Gemini models ignore the marker, and other providers get the
  line without it. To turn the marker off, set `prompt_cache: false` in the
  `ai_gateway:` block of `config/llm.yml`; no setting is needed to keep it on.
  The manager files are now always sent sorted by file name. (rev 2264)

## [4.7.3] — 2026-10-08

**Upgrade notes.** No migration; a change to `config/queue.yml` and
`config/recurring.yml` that the deploy's Solid Queue restart picks up. After
deploying, Manage → Grader Processes → Job Workers should list one worker on
`viva` and one on `*`. The scheduled-task requests that had piled up were
discarded on every deployed web host on 2026-10-08 at about 11:10; whatever
queued after that (a few hundred a day, including one nightly clean-up per
night) runs once when the new worker starts. If the deploy happens a day or
more later, discard them again just before it
(`SolidQueue::Queue.find_by_name('solid_queue_recurring').clear` in a
production runner), so the large first clean-up runs at 02:00 rather than at
deploy time. Deploying 4.7.2 and 4.7.3 together is fine.

### Fixed
- **Scheduled housekeeping had stopped on every server since the 2026-09-17
  deploy.** The nightly clean-up of old grading-job rows and compiled
  programs, the viva failsafe (fails an examiner reply that never arrives),
  the abandoned-viva reaper, the stuck-grading-job reclaim and the audit-log
  clean-up were all queued on time but never run: Solid Queue puts every
  scheduled command in its own queue, and since the 2026-09-12 split into a
  viva worker and a default worker no worker served it. The default worker
  now serves every queue; the viva worker still serves only interview turns
  and viva grading, so nothing can hold those up. Grading itself was never
  affected. The unrun requests (about 9,550 per server) were discarded on
  2026-10-08, so after deploying each task catches up once at its normal
  time: on cp-grader the 02:00 clean-up deletes about 244,000 old grading-job
  rows and the compiled programs of about 15,000 graded submissions, and the
  hourly reaper closes 11 abandoned viva sessions (one is sent for grading).
  (rev 2258)
- **Hall of Fame counts were never refreshed.** The hourly task that
  recomputes them was written where Solid Queue does not read scheduled
  tasks, so cp-grader showed counts from 2026-04-17 and other servers showed
  none. It now runs every hour (7 seconds on cp-grader). (rev 2258)
- A viva examiner reply that never arrived was marked "no response after 10
  minutes" although the rule that failed it waits 20; the message now names
  the wait that applied. (rev 2258)

## [4.7.2] — 2026-10-08

**Upgrade notes.** Run `bin/rails db:migrate` — four migrations: the
`right.login_throttle_exempt_ips` setting (created empty); two nullable
columns on `submissions` for viva retakes (added in place, but the ALTER
briefly waits for a lock on `submissions`); an index on `jobs.arg`; and the
evaluations clean-up plus a unique index on `(submission_id, testcase_id)`
(about 30 seconds on cp-grader's 7.6 million rows; grading goes on during
it). Run them outside exam hours. Deploy a web host before its judge host,
or both together: the new judge code looks jobs up by submission and is slow
until the `jobs.arg` index exists. After deploying, put each exam gateway's
address in `right.login_throttle_exempt_ips` on the System configuration
page. The new checker and initializer time bounds need no configuration.
Going back to 4.7.1: `bin/rails db:rollback:primary STEP=2` restores the old
evaluations index (the deleted orphan rows stay deleted); the viva columns
and the setting can stay.

### Added
- **Exam gateways no longer lock a whole room out of login.** The login
  lock counts failed passwords per account and per address (30 within 3
  minutes). When every student reaches the server through one exam gateway,
  the whole room shares that address, so a few minutes of wrong passwords
  locked everyone out: in DS Quiz 2 (2026-10-07) a CU-net password switch
  left off for four minutes refused 113 logins. New setting
  `right.login_throttle_exempt_ips` (comma-separated addresses or CIDR
  ranges, created empty by a data migration) lists addresses that skip the
  per-address count; each account still locks after 30 failures. After
  deploying, put the exam gateway's address in it. (rev 2232) Login skips
  a mistyped entry without an error, so the System configuration page
  shows a warning under the setting instead: for an entry that is not an
  address or range (e.g. `10.0.5.40;10.0.5.41`, joined by a semicolon),
  which exempts nothing, and for a range that covers every address (e.g.
  `0.0.0.0/0`), which switches the per-address count off for everyone.
  (rev 2250)
- **Clear Login Locks** button on the System configuration page, beside
  Clear Device Locks: unlocks every address and account blocked by "Too
  many failed login attempts" at once and names what was locked. Before,
  the only ways out were waiting up to 3 minutes or deleting the counter
  from a Rails console. (rev 2232)
- **Viva check** page for each contest (contest page → Reports → Viva
  check): one row per student per viva problem with the flags staff should
  act on (students only: staff sessions are left out) — Retook, Waiting for
  reply, Reply failed, Grading failed, Left
  unfinished, Grade doesn't add up (a rubric item above its maximum or items
  not summing to the total), Rubric unreadable — and the ones worth a look
  (No answer yet, Short but high, Ended early, Rule-break flag). It reloads
  every 30 seconds while the contest runs; an "N to check" badge next to the
  viva grading status on the contest page counts the students who need
  action. Built after proctors saw students take the DS Quiz 2 viva twice.
  (revs 2242, 2244, 2247)
- **Allow another attempt** (staff who can edit the problem, in contest
  mode too): archives a viva session at any status — including an open
  interview after an infrastructure failure — and stops it counting toward
  the start limit, so the student can start one more. The closed session
  takes no more answers or retries and is never graded, even when an
  examiner reply already on its way would have ended the interview. The
  confirmation says what the student can do now: start again (with the
  starts left), or not yet, because another answered session of theirs
  today still counts — shown as a warning, so staff grant that session too.
  On the session page's Admin card, replacing "Archive & allow retake", and
  on each student row of Viva check. Each grant is an audit row on the
  problem. Run `bin/rails db:migrate` (two nullable columns on
  `submissions`, added without a table copy). Run the migration outside
  exam hours: the ALTER briefly waits for a lock on `submissions`. (revs
  2238, 2240, 2244, 2247, 2249)

### Changed
- **Viva start limit 0 means one attempt in a contest.** "Contest-only"
  vivas used to allow unlimited restarts during contest mode; now a student
  gets one counted session (a session counts once they answer), the same as
  limit 1. For an exam set the limit to 1 (or 0): a practice value lets
  students finish, restart and retake, and the best session counts. One
  rule (`Viva::StartPolicy`) now drives Start, Restart and the session
  page. (revs 2238, 2239)
- **Viva Restart is offered only when the student could start again.**
  Under limit 1, Restart in the middle of an interview used to archive the
  session ungraded and leave the student unable to start a new one. The
  button now reads "Restart viva" (was "Restart practice viva"), since it
  also shows during exams. The session page's archived note now says
  whether the session's score still counts toward the best or it was
  closed without a grade. (revs 2239, 2247, 2249)
- **Submissions and User Activity reports:** Login (the link) and Name are
  separate columns, as on the problem stat page and the Best Score report,
  instead of "(login) name". With a contest picked, the login opens the
  student's stat page for that contest. The problem column links the full
  name, with the short name in grey after it; copy/Excel exports keep
  "[name] full name". (rev 2235)
- **Contest AI Usage:** a "total AI cost" tile — viva turns + viva grading +
  priced assists — with the three parts underneath, in place of the
  assist-only dollars tile. (rev 2235)
- **Problem stat page of a viva problem** says that staff test-drives are not
  counted on the page, and how many there are. (rev 2235)

### Fixed
- **A custom checker or dataset initializer that never finished held its
  grader box forever.** Both ran on the judge host with no time bound, so
  one checker stuck in a loop stopped that box from taking any other job.
  A checker is now stopped after 30 seconds (that testcase shows `!` with
  "checker timed out after 30 s"; the other testcases still run), and an
  initializer after 120 seconds (the submission gets a grading error and
  the next job on that worker initializes the dataset again); whatever they
  started is stopped with them. A host can change the two bounds in
  `config/worker.yml` under `limits:` (see `worker.yml.SAMPLE`). As a last
  resort the every-minute watchdog now kills a grader that has not reported
  for 10 minutes while its box is enabled; the job goes back to the queue
  and a fresh grader starts. (rev 2251)
- **Retry All on the Graders page no longer re-runs jobs a rejudge has
  replaced.** It put every failed job back in the queue, including failed
  jobs from a grading that a later rejudge had already restarted, so two
  gradings of one submission ran at once. Retry and Retry All now re-queue
  a failed job only when its submission still exists, has not been graded
  since, and has not been rejudged since; the message says how many were
  skipped. Clear All is unchanged. (rev 2252)
- **A rejudge while a submission was still being graded could leave a wrong
  score or "Evaluations are missing, please rejudge."** The rejudge started
  a second grading but the first kept running, and both wrote the same
  per-testcase results; after a rejudge onto another dataset, the first
  grading's late scoring step failed the new one. Now a rejudge stops the
  first grading: its queued jobs fail with "superseded by rejudge" (they
  show among the Graders page's failed jobs, and Retry skips them), and a
  job already running checks before each write and drops its result. The
  database now holds at most one result per submission and testcase. Run
  `bin/rails db:migrate` (two migrations): it deletes per-testcase results
  whose submission no longer exists (4,279 rows on cp-grader, none of them
  visible anywhere), keeps the newest of any duplicate, and adds a unique
  index — about 30 seconds on cp-grader's 7.6 million rows. Grading goes on
  during it, but run it outside exam hours. (rev 2253)

## [4.7.1] — 2026-10-03

**Upgrade notes.** A gem update only: no migration, no new setting, no
config change. The deploy's `bundle install` fetches the new gems (three of
them — rdiscount, msgpack, json — build native extensions, as they did
before). Going back to 4.7.0 needs nothing but the previous revision and
`bundle install`; the old gem versions stay installed alongside the new ones.

### Security
- **Gem update** that clears 74 of the 78 security advisories GitHub reports
  against `Gemfile.lock`, every gem staying within its current major version:
  Rails 8.0.2 → 8.0.5.1 (Active Storage arbitrary file read and path
  traversal), rack 3.1.22, rack-session 2.1.2, nokogiri 1.19.4, jwt 3.3.0,
  rails-html-sanitizer 1.7.1, faraday 2.14.4, net-imap 0.5.15, mail 2.9.1,
  loofah 2.25.2, rdiscount 2.2.7.5 and smaller ones. The `concurrent-ruby`
  1.3.4 pin, a workaround from the Rails 7.0 days, is lifted. No migration;
  the deploy's `bundle install` is the only host step. Left for a separate
  step because each is a major-version jump: puma 7 (the development server —
  production runs Passenger), rubyzip 3 (pulled in only by the system-test
  browser driver) and erb 6 (pulled in by rdoc). (rev 2225)

## [4.7.0] — 2026-10-01

**Upgrade notes.** Run `bin/rails db:migrate` — this release carries 5
migrations: `llm_started_at` / `llm_latency_ms` on `viva_turns`, `comments`
and `viva_grades`; `submissions.test_drive`; the viva grade history
(`viva_grades.superseded_at` / `superseded_reason` / `superseded_by_id` /
`requested_by_id` / `batch_id` / `error`, the unique index on
`submission_id` replaced by `(submission_id, superseded_at)`); a data
migration that files legacy failed grade rows as history; and
`grader_processes.disk_free_mb`. Stop the Solid Queue workers while the two
viva_grades migrations run (a grading job landing between them could write a
row the data migration then relabels); a judge host deployed before the web
host migrated skips its disk-space write, so judge/web order does not matter.
Run `bin/rails db:seed` once to add the `ui.testcase_preview_bytes` setting
(without it the default of 2048 bytes applies). Three entries are security
fixes — stored XSS through announcements, comment titles and compiler
messages, a per-problem testcase flag the downloads and API ignored, and the
site-mode switch reachable by any group editor — so servers whose TAs hold the
group-editor role should not wait. Behaviour changes worth knowing before
upgrading a live server: the Submissions page opens on every submission the
student can see, newest first, instead of asking for a problem; viva
interviews and grading run on their own job queue and worker (`viva`) beside
`default`, sized to the stock database pool so no host configuration is
needed, with `config/solid_queue.env.SAMPLE` showing the per-host override;
the deploy's `engine:smoke SUB=auto` step must run from a pipeline that
carries it (a retried older pipeline does not); the student `/main/help` page
is gone; Go judge hosts need the new engine for the raised open-file limit.

### Added
- **Free disk space per judge host on the Grader Processes page** (issue
  #25). Each judge worker measures the free space of its judge directory and
  isolate box root once a minute and stores the smaller figure; the web host
  measures its app and storage directories when the page renders. The
  Background Workers card gets a fourth tile with the lowest figure, red when
  any host is under 2 GB, and a per-host line underneath. One migration
  (`grader_processes.disk_free_mb`). (rev 2215)
- **Testcase page shows a preview, not the whole dataset.** Students who may
  view a problem's test data now see the first 2 KB of each input, expected
  output and run-time data file, with the file's size and a "truncated"
  badge, and no download buttons; admins, reporters and editors of the
  problem keep whole-file downloads (the page shows them the same prefix).
  The amount is the new site setting `ui.testcase_preview_bytes` (0 = whole
  files and downloads for everyone, the old behaviour); run `db:seed` to add
  the key, or the default 2048 applies. Compile-time manager files stay whole
  for every tier. The JSON API follows the same tier: `/testcases/{id}/input`
  and `/sol` return the prefix with `X-Testcase-Byte-Size` and
  `X-Testcase-Truncated` headers, and `/problems/{id}/testcases` lists
  `access`, `input_bytes` and `sol_bytes`. Fixes the page that pulled every
  file whole (one visible problem served 244 MB per visit, issue #59) and
  closes issue #18 (run-time data files were never shown). (rev 2218)
- **My Submissions lists everything, newest first.** The Submissions page
  no longer opens on "Select a problem": it shows all your submissions across
  every problem you can open, newest first, 50 a page (Newer / Older links),
  with a **Problem** column linking to that problem's own list. The problem
  picker is now a filter; the × on the picker or the **All problems** button
  on a filtered page returns to the full list. The per-problem list is paged
  the same way.
  Contest mode keeps its rule: only submissions inside your active contests'
  windows are listed. Requested in issue #62. (rev 2211)
- **A contest as the scope of the Best Score, Submissions and User Activity
  reports.** A **Contest** picker in each report's title row (contests you
  manage) reloads the page with `?contest=ID`: the three filter cards give
  way to one line naming the contest, and the report covers its students
  (the rows its Watch page lists), its problems you may report on, and each
  student's own window — start offset and extra time included, which the
  date-range filter could never express. Best Score then shows the Watch
  page's numbers with the contest seat and remark, and loads at once;
  User Activity's "zero submissions" option lists the students who never
  submitted in their window. The contest management page gets a
  **Reports** menu opening the three with the contest picked. A contest you
  cannot manage is ignored and the page says so. The AI Assist report has
  no picker (it reads the job queue by submission number) and points at
  the contest's AI Usage page instead. (rev 2209)
- **Viva grading status on the contest page.** Next to **Finish open vivas**,
  a badge shows how many of the contest's viva sessions are still being
  graded and how many failed grading, refreshing itself every 10 seconds
  while anything is in progress, and reads **All vivas graded** once the
  scores are final. (rev 2201)
- **Viva grade history and batch regrade.** Every grader run is now kept:
  the viva session page's Admin card lists each run (time, model, total,
  rubric version, who asked, outcome) with a **Raw** toggle and a **Make
  current** button that puts an earlier grade back. **Re-run grading** no
  longer discards the current grade: the student keeps it until the new run
  is adopted, a new **Keep the higher grade** checkbox (on by default) files
  a lower re-run away instead of applying it, a failed re-run never removes
  a grade, and an open interview can no longer be re-run. New rake tasks
  `viva:regrade PROBLEM= [CONTEST=] [MODEL=] [ALL=1] [REPLACE=1] [LIMIT=]
  [APPLY=1]` (stale grades only by default, one audit row per batch; batch
  runs queue at a lower priority than live interview turns and the report
  warns how many viva sessions are open),
  `viva:regrade_status BATCH=` and `viva:regrade_revert BATCH=` replace the
  hand-run regrade toolkit. `viva_grades.rubric_version` is written on every
  run. Adds six columns to `viva_grades` and drops its unique index, and a
  second migration files legacy failed grade rows as history (migrations).
  (rev 2183–2197)
- **Viva test-drives: sit your own viva without polluting the data.** The
  problem edit page shows a **Test-drive** button on viva problems (editors of
  the problem's group and admins). The admin problem index offers the same
  button on viva rows in place of the former staff "Start Viva". It runs a
  real interview and grading, but the session is flagged as a test-drive:
  excluded from the problem list, scores, contest scoreboards, every Report
  page, the stat pages, the AI-usage report and the API; not counted against
  the author's daily starts; not blocked by the contest-only rule;
  restartable without limit. Test-drives are listed in the Viva Exam card of
  the edit page and badged on the viva session, viva alerts and stuck-turns
  pages. Other students never see them, even when a problem shares
  transcripts. Adds `submissions.test_drive` (migration). (rev 2167–2173)
- **"Finish open vivas" button on the contest management page** (contest
  editors and admins). One click closes every viva session of the contest
  that is still open — started inside the contest window by an enrolled
  student, not yet ended or archived: a session with at least one student
  answer is closed and sent to grading, a greeting-only session is archived,
  and a session whose assistant reply is still in flight is skipped and
  counted so staff can click again. The confirm names the current count, a
  toast reports the three counts, and one audit row records them. At the
  2026-09-09 quiz bell 65 of 151 sessions were still open and were finalised
  by 62 manual Re-run clicks. The 24-hour abandoned-session reaper remains
  the safety net and now shares this exact finishing step, including the row
  lock the student End button uses. (rev 2161)

- **AI-usage report, per contest** (Manage/Watch → AI Usage, or
  `/contests/:id/ai_usage`; admins and contest editors). Shows viva-interview,
  grading and assist volume, cost, and response-time percentiles (mean / p50 /
  p90 / p95 / p99 / max) over the contest window, with per-5-minute charts, a
  per-model and per-problem breakdown, the students who opened a viva but never
  answered, and a searchable per-call table. Response time is now recorded per
  call split into queue time and provider time (`llm_started_at` /
  `llm_latency_ms` on viva turns, comments and viva grades); calls made before
  this release show only the combined total. (rev 2136, 2140, 2141)

- **Grader Processes page shows the Solid Queue workers as they actually
  run** — a "Job Workers" card listing every registered process (supervisor,
  dispatcher, scheduler, workers) with its queues, thread pool, heartbeat age
  and host. The thread pool shown is the effective value after any per-host
  override, so an operator can confirm what a host runs without reading
  config files; a row with a heartbeat older than the prune threshold turns
  red. (rev 2151)

- **Deploy pipeline smoke-grades one real submission before anything
  restarts.** `bin/rails engine:smoke SUB=auto` lets the new
  `EngineSmokePicker` choose a recent full-score C++ / C / Python submission on
  the host — graded after its live dataset last changed, slowest testcase
  within half the time limit, at most 60 s of worst-case run — regrades it
  with the freshly checked-out engine, restores it, and exits non-zero on an
  engine error or a differing verdict. The deploy job runs it right after
  asset precompile and before Solid Queue, Passenger and the judge graders
  restart, so a broken engine never reaches the long-lived grader processes.
  Web-only hosts and hosts with no suitable submission print `SKIPPED` and
  continue. (rev 2155; automation repo rev 63)

### Changed
- **The old student help page (`/main/help`) is removed** (issue #35). Its
  2013-era "how to submit" text had been outdated for years and had already
  lost its navbar link; the route, view, locale keys and dead menu entries go
  with it. A student help link, when one returns, will point at the wiki.
  (rev 2213)
- **The contest AI Usage page separates the AI's own time from the wait.**
  "Wait time distribution" and "Assist by model" now show, beside each
  wait, the mean and p95 of the AI time (how long the provider took to
  answer, recorded since rev 2135), so a slow model can be told apart from
  a backed-up queue. Every wait column is labelled in seconds, the p50–p99
  headers explain themselves on hover and in a note, and the per-call table
  reads Queue s / AI s / Wait s. Calls made before a server recorded AI
  time show "–". (rev 2207)
- A viva's `submissions.graded_at` now follows the adopted grader run (Make
  current or a batch regrade moves it). Reports still bucket a viva by
  `submitted_at`, its session start, so a regrade never moves a session out
  of its contest. The contest AI-usage report marks failed grader runs
  `error` instead of `ok`. (rev 2185, 2190)
- **Viva interviews and grading now run on their own background-job queue
  and worker**, isolated from AI-assist requests. During the 2026-09-09 quiz
  one 3-thread worker served interview turns, grading and assists together;
  when assist traffic spiked, interview responses queued for up to ~7.5
  minutes and seven students never received their first question. Two
  workers now: `viva` (turns + grading) and `default` (everything else), 3
  threads each — sized to fit the stock database pool of 5, so no host
  configuration change is needed to deploy. Per-host tuning via
  `VIVA_JOB_THREADS` / `JOB_THREADS`, raising `RAILS_MAX_THREADS` with them
  (threads must stay at most pool minus one). (rev 2137, 2146)

### Security
- **Stored XSS through staff-written text (issue #50, vectors 2–4) and
  compiler messages.** Four places rendered text as HTML that someone other
  than an admin controls: announcement bodies (an editor's `<script>` ran in
  every visitor's browser, including the navbar strip), submission-comment
  and hint titles and bodies (in the comment list, the create/update toast
  and the View modal, so a TA's comment ran in the student's and every
  reviewer's browser), and the compiler message (compilers echo source
  lines, so one `#error` line in a student's code ran in whichever staff
  member opened the message). Titles and compiler output are now plain
  text. Announcement, hint and comment bodies render through an HTML
  allow-list (`sanitized_markdown`): the HTML staff actually use in
  production bodies — links that open a new tab, `<font>` size and colour,
  tables, images — keeps working, while script, iframes and event handlers
  are dropped. A running AI-assist row still shows its spinner; it is now
  drawn from the request's status instead of markup stored in the title.
  Vector 1 of the report was fixed in rev 1536 / 2079 and the AI-assist body
  in rev 2084. (rev 2220)
- Testcase downloads and the API checked only the site-wide `right.view_testcase`,
  not the problem's own "view testcase" flag: a student could fetch the test
  files of a problem whose flag was off while the page refused them. One
  predicate (`User#testcase_access`) now checks both everywhere. (rev 2218)
- **Switching the site mode (standard/contest/analysis) now requires an
  admin.** It was reachable by any group editor; a TA flipped the whole site's
  mode mid-exam on 2026-09-09. (rev 2141)

### Fixed
- **A custom checker whose filename contained a space or a shell character
  failed every testcase with a grader error** (issue #49). The checker keeps
  its uploaded filename on the judge host, and the check command was built as
  a shell string, so a checker uploaded as `checker (1)` was parsed by the
  shell. Every evaluator (diff, relative, postgres, the custom ones) now runs
  its checker as an argument list, with the argument order unchanged.
  (rev 2212)
- **Go submissions that import `fmt` or `os` failed to compile with
  "pipe2: too many open files"** (issue #40). isolate caps a sandbox at 64
  open files and `go build` needs more; the Go sandbox options now raise the
  limit to 1024 for compile and run. (rev 2214)
- **A queue backlog no longer shows viva students a false "timed out".** A
  turn queued but never started counts as stale after 20 minutes, not the 10
  that applies to a turn the model started and then hung on. (rev 2142)
- The AI Usage page's charts threw "Canvas is already in use" and could draw
  twice when their data was present at page load. (rev 2143)
- The submission status line read "submitted3 minutes ago" and
  "1 day ago(30/09/26 …)"; the words now have spaces between them, on the
  problem list as well. (rev 2211)
- **The Submissions report ignored its Users card** — an assignment written
  where a comparison was meant (`unless @users = User.all`, 2024-09-30) made
  every query list every user's submissions on the chosen problems, so a
  reporter also saw students outside their groups who had submitted to a
  shared problem. The card's choice now applies, as on the other reports.
  (rev 2209)
- **The contest AI Usage page counted only viva grades that finished before
  the window closed.** Grading usually lands after the bell (Finish open
  vivas) and regrades later still, so DS Quiz 1 showed 23 grades of its 151
  and under-reported the grading cost. A grading run now counts when its
  viva session started inside the contest window, however late it ran, and
  the page says how many ran after the window. The per-call table's Status
  column, blank for every viva turn and assist, now shows ok / error /
  processing, and its Time column carries the date. (rev 2207)
- **The deploy's smoke check no longer fails on, or relabels, an old
  submission whose problem has since been limited to another language.**
  On comprog-grader on 2026-09-25 `engine:smoke SUB=auto` picked a 2024 C++
  submission on a problem that now accepts only Python; grading saves the
  submission, the save relabels it to the problem's only language, the C++
  ran as Python and every testcase crashed, so the deploy stopped on a false
  "verdict DIFFERS" (exit 2) — and the submission was left labelled Python.
  The picker now skips a submission whose language its problem no longer
  accepts, the check restores the submission's language along with its
  grade, and it grades from no stored testcase results, as a real regrade
  does, so a crashed testcase no longer shows its old score in the log.
  (rev 2203)
- **A browser refused by the device lock ("You cannot login from two
  different places") is now logged out, not just redirected.** A refused
  window used to keep its session, so its contest heartbeat kept polling and
  retook the lock within seconds of every admin reset; on ise-grader on
  2026-09-22 a student with a forgotten second window could not get back in
  through eleven resets by the TAs and the admin. The refused browser keeps
  its device cookie, so it is recognised again after a reset; the heartbeat
  poller also stops once it is bounced to the login page instead of retrying
  every 5 seconds. (rev 2159)
- **Audit rows no longer vanish when a record is reloaded or saved again
  before its transaction commits.** The `Auditable` concern read
  `saved_changes` in the commit callback, which describes only the last save
  and is cleared by `reload`; `viva:import APPLY=1` reloads every problem it
  touched for its post-check, so a live briefing rewrite on 2026-09-09 left
  no `AuditLog` row. Changes are now staged at save time and written at
  commit: one row per record per transaction with the first old and last new
  value, a rollback discards the staged diff, and `AuditLog.paused` now also
  works around a save inside an outer transaction. `Problem#description`
  (statement / viva scenario) is audited too, stored in full. (rev 2157)
- **Every page 500'd for a logged-in user whose session pointed at an enabled
  contest they were not enrolled in.** In contest mode the navbar countdown
  read `extra_time_second` off a nil contest-membership. It now treats a
  missing membership as zero extra time. (rev 2139)
- **Score/max-score reports crashed with a 500 in contest mode for group
  editors.** The contest-mode report problem scope was a `SELECT DISTINCT
  problems.id` relation; ordering it by `date_added` (the score report) under
  MySQL 8 `ONLY_FULL_GROUP_BY` raised "ORDER BY ... incompatible with
  DISTINCT". Staff hit this on the 2026-09-09 quiz. The scope now returns a
  `Problem.where(id: <subquery>)`, which is orderable; the problem set is
  unchanged. (rev 2138)
- **Grader Processes page crashed with a 500 when an error job had no
  submission.** The Failed Jobs table linked every error job to its
  submission; a job whose submission was deleted before the orphan reclaim
  (4.6.0) gave up on it has no submission id, and building that link raised.
  cedt-grader had three such rows from December 2023 among the fifty most
  recent error jobs, so the page failed on every visit from 30 August. The
  cell now reads "deleted" for such a job. (rev 2130)
- **The navbar "N backlogs!" badge counted ungraded viva sessions.** The
  badge and the monitor page it links to counted different things: the page
  excluded viva sessions (LLM-graded, never on the judge queue), the badge
  did not, so a server with abandoned viva sessions showed a permanent
  backlog while its judge queue was empty (cedt-grader: badge 48, all viva,
  queue 0). Both now read one scope, `Submission.judge_backlog`. (rev 2130)

## [4.6.0] — 2026-09-10

**Upgrade notes.** Run `bin/rails db:migrate` — this release carries 5
migrations (`users.verdict_display`; `comments.llm_cost` / `prompt_tokens` /
`completion_tokens`; a data migration that creates the `system.llm_assist_cost`
setting at 10 where it is absent; the `jobs (status, priority DESC, id)` index;
`groups.created_at` / `updated_at`). Three entries are security fixes — stored
XSS through the admin DataTables, AI-assist answers rendered as raw HTML, and
an assist request any logged-in user could charge to another student — so
servers with self-registration or AI assist should not wait. Behaviour changes
worth knowing before upgrading a live server: the evaluation types `custom_cms`
/ `custom_cms_raw` are now `custom_testlib` / `custom_testlib_raw` (stored
values unchanged, the old names still accepted on input, exported packages
carry the new ones); the nightly job cleanup also deletes `error` jobs older
than 30 days; an admin's AI-assist request costs the student nothing, the
student's own requests cost the new site setting, and the picker refuses
requests that cannot help; the first `grader_job_reclaim` sweep surfaces
long-stranded jobs as error rows on the Grader Processes page, where they can
be cleared. After deploying to a judge host, run `bin/rails engine:smoke
SUB=<id>` once on a submission you are happy to see re-evaluated — it is the
check that would have caught the 2026-08-30 outage. Optional:
`rake comments:backfill_llm_usage` recovers token counts for earlier assist
answers.

### Added
- **Groups index shows when each group was created and lists newest first.**
  A new sortable "Created" column, and the default order is created date,
  newest first, then id descending (the list used to come out in whatever
  order the database returned it). Groups made before this release have no
  recorded creation date anywhere, so their cell is blank and they sit at the
  bottom in id order; a migration adds `created_at` / `updated_at` to
  `groups`. (rev 2126)
- **Stat pages show what AI assistance cost, per model.** The user stat card
  (and its per-contest variant) and a new "AI assist" card on the problem stat
  page list, per model, the requests on the student's or problem's
  submissions, how many were answered, the points charged, the provider's
  dollar figure where it reported one (with an "n of m priced" note when only
  some rows carry it) and the tokens in / out. Requests are attributed to the
  submission's owner — who is charged — rather than to whoever pressed Get, so
  the card's "AI Assist" total now follows the same rule. (rev 2117)
- **AI assist sends the model what the grader already knows.** The payload
  now carries the compiler output when the submission did not compile (166
  assisted compile errors in production history got a prompt asking the model
  to spot the syntax error blind), the per-testcase table from the stored
  evaluations — group, verdict, time, memory, score, plus the dataset's
  limits — instead of leaving the model to infer subtask boundaries from
  percentages in the statement PDF, and, on a repeat request for the same
  problem, the previous answer with a line diff of what the student changed
  since, so the model builds on its last hint instead of repeating it (40% of
  student–problem pairs asked more than once; the model saw none of it).
  Nothing in the table reveals test data. The `llm_prompt` tags' "How to
  Map" section is now redundant and can be deleted. (rev 2089)
- **AI assist records the provider's own accounting.** New `comments`
  columns `llm_cost` (dollars, from the gateway's cost header; nil where the
  provider reports none, 0.0 for self-hosted models), `prompt_tokens` and
  `completion_tokens`. `cost` stays the score penalty. `rake
  comments:backfill_llm_usage` recovers the token counts for earlier rows from
  the stored response (present on 4,492 of 4,577 production answers); the
  dollar figure cannot be recovered. (rev 2089)
- **Problem stat page: "By group" card.** One row per section (group) the
  viewer may report on: members, solved / attempted, solved %, mean best
  score over students who attempted, each row linking to the Best Score
  report pre-filtered to that group. Sections can now be compared at a
  glance, which the report itself cannot show since it lists one group at a
  time. Members are enabled `user`-role rows only, so staff test submissions
  do not move a section's numbers; a student in several groups counts in
  each row, so rows may sum to more than the distinct-user summary. (rev 2081)
  Archived cohorts stay linked to a problem for good and would add rows every
  semester, so they fold behind an "N archived groups" toggle while at least
  one live group is shown; a problem linked only to archived groups shows
  them open. (rev 2082)
- **`bin/rails engine:smoke SUB=<id> [BOX=99]`** — grades one existing
  submission end to end on this host with the real sandbox (compile → every
  testcase → score, exactly as a grader would), prints each testcase's verdict
  and the run's grade next to the stored one, then restores the submission
  and its evaluations as found. Exit 0 identical, 2 differs, 1 engine error.
  Use it on a worker right after a deploy, on a submission you are happy to
  see re-evaluated, with a box id no grader owns. Added after the 2026-08-30
  outage, which no test without isolate could see and this shows in seconds.
  Alongside it, a CI-runnable Evaluator→Checker flow test with only the
  sandbox and downloads faked (`test/engine/evaluator_checker_flow_test.rb`)
  now fails on the rev-2045 bug. (rev 2063)
- **Problem-list status filter** ([#29](https://github.com/nattee/cafe-grader-web/issues/29)) —
  the student main list gains a segmented **All | Unsolved | In progress |
  Solved** filter and a **Random** button that jumps to (and flash-highlights)
  a random untried problem; the chosen filter is remembered per browser. The
  constant "Showing 1 to N of N entries" line is replaced by a compact counter
  ("42 of 199 problems") that follows every filter, including topic and text
  search. (rev 2067)
- **Per-user test-result display preference** — Profile → Preferences gains a
  "Test-result display" choice: colour tiles (the default) or the pre-4.5
  plain-text rendering ("[PP-T]"), applied everywhere grader results are
  shown (problem list, submission detail, stats pages, reports). Requested by
  users who preferred the original compact text. (rev 2068)

### Changed
- **An admin's AI-assist request no longer charges the student.** Only the
  submission's owner or an admin may press Get (rev 2084); when an admin asks
  on a student's behalf, the stored charge is now 0 points and the confirm
  dialog says the request does not reduce the full score — the student did
  not ask, so the penalty is not theirs. The provider's dollar cost and
  tokens are still recorded; the owner's own requests pay the site price as
  before. (rev 2116)
- **Nightly job cleanup also purges `error` jobs after 30 days.**
  `Job.clean_old_job` removed only `success` rows, so failed job rows lived
  forever and joined every judge poll scan — on 2026-09-08 comprog still
  carried 4,422 rows from the 2026-08-30 outage. Error rows now stay 30 days
  as the debugging trail (the Graders page lists the latest 50 with Retry
  All / Clear All), then go. (rev 2115)
- **AI-assist price is a site setting.** The points a request costs were a
  constant in code (10). They are now `system.llm_assist_cost` on the
  Configuration page (created at 10 by a data migration on deploy, rev 2111,
  and by `bin/rails db:seed` on a fresh install; the code falls back to 10
  while the key is absent). The value is read when the request is made
  and recorded on it, so changing it never rewrites past charges; 0 makes
  assistance free. The confirm dialog quotes the current value. (rev 2100)
- **AI-assist prompt tags assemble in name order.** A problem with several
  `llm_prompt` tags sends each as its own system part; they now go in tag-name
  order instead of attach order, so a shared core tag plus a small per-course
  addendum (the Chula deployment now uses `codey-core` + `codey-thai` instead
  of two full copies of the prompt) reads the same on every problem. (rev 2093)
- **AI-assist picker refuses requests that cannot help.** "Get" is disabled,
  with the reason beside it, while a request on that submission is still
  running, when that model has already answered the submission, when the
  submission already has full score, and once the student has spent the full
  score of the problem on AI help; the server applies the same rule, so a
  replayed form gets the same refusal. The picker refreshes together with
  the comments, so a finished request re-enables Get without a reload.
  Production history before this: 190 submissions had the same model asked
  twice, 126 requests were made on full-score submissions, and 10
  student–problem pairs had spent more than the problem was worth. (rev 2090)
- **Problem stat page loads in a fraction of the time on busy problems.** The
  page used to pull every submission of the problem into Ruby to compute two
  numbers (plus a histogram nothing displayed), then render every row into
  the HTML for the browser to sort. The summary is now two grouped queries and
  the submissions table is filled by an AJAX request, paged 50 at a time with
  deferred rendering, so the page paints before a single row exists. On the
  heaviest problem in the production copy (7,825 submissions) the page's own
  server work drops from about 1.2 s of Ruby to about 0.4 s of SQL; the row
  list (about 0.2 s) is fetched separately once the page is up, and the
  browser no longer receives 7,825 table rows to sort. Same columns as
  before; scores now sort numerically. (rev 2081)
- **Viva kit importer: several conduct tags per kit** — `manifest.yml` now takes
  a `conduct_tags:` list (the legacy single `conduct_tag:` still works); every
  listed tag is upserted by name and linked, add-only, to every problem in the
  kit, and the same name listed twice fails the import. Lets a course split its
  examiner conduct into a mode-invariant profile plus a practice/exam overlay
  (`Problem#viva_conduct_tags` concatenates them in name order, so overlays
  are named as suffixes of the profile). (rev 2071)
- **LLM gateway cost accounting no longer assumes LiteLLM.** A hosted gateway's
  per-call cost is now resolved from the `x-litellm-response-cost` header
  first, then `usage.cost` in the response body; a call with neither logs a
  WARN naming the model instead of silently recording $0.00. The old behaviour
  quietly zeroed cost reporting whenever cost tracking was off on the proxy, a
  model was missing from its price map, or a proxy upgrade dropped the header —
  invisible until the totals were already wrong. A genuine `0` in the header
  stays authoritative. New optional `ai_gateway.usage_in_body` key in
  `config/llm.yml` sends `usage: {include: true}` for gateways that report cost
  in the response body (OpenRouter-style aggregators); leave it unset for
  LiteLLM. `config/llm.yml` also gains a worked — and explicitly unverified —
  OpenRouter example; mind the `base_url`/`completion_path` split it documents,
  since an absolute path replaces `base_url`'s own path. (rev 2050)
- **Evaluation types renamed**: `custom_cms` → `custom_testlib` and
  `custom_cms_raw` → `custom_testlib_raw`. The old names described the *result
  protocol* (score on stdout, `translate:*` on stderr) but not the argument
  order, which is testlib/Codeforces's `(input, user, correct)` — not CMS's
  `(input, correct, user)`; that order is `cms_comparator`. Stored values are
  unchanged (no migration, nothing to re-save); the old names remain accepted
  in the dataset form, the JSON API and import packages
  (`Dataset::LEGACY_EVALUATION_TYPES`), while exported packages now carry the
  new names. The dataset settings dropdown also offers `cms_comparator` as
  **[CMS-NATIVE]** (previously reachable only through `cms:clone`), and the
  Checker section now appears for it; every dropdown label now shows its enum
  key (`[TESTLIB] custom_testlib — …`), the name used by packages and the API
  (rev 2048). Every deployed problem on the renamed types was
  verified beforehand to expect the testlib order (`doc/decisions.md`
  2026-08-29). (rev 2047)
- Main list "Latest Results": the per-testcase verdict string (`PP-T`,
  `[PPPP][PP-]`) is now drawn as a strip of colour-coded tiles — one per
  testcase, `[…]` groups boxed and never split across lines — inside a
  fixed-width block, so problems with 40–80 testcases no longer widen the
  column and squeeze the problem name. A labelled `legend` pill in the column
  header explains the tiles and boxes; every tile and box carries hover
  details ("Test 7 of 40: Wrong Answer", "Group 2 of 5: 3/5 passed…"), and the
  Evaluation Details modal gains a one-line key for grouped tests. Free-text
  comments ("No testcase", checker messages) keep the plain rendering,
  width-capped. The per-problem submission list shares the partial and gets
  the same strip (rev 2039). The submission detail page, problem and user
  statistics, the grader monitor, the near-miss repair view and the
  submission report (client-side, same tiles) use it too (rev 2041).

### Fixed
- **The user stat page showed no hints for students.** Its "Hints" row counted
  hints the user had *written* (the comment's author), so it was blank on
  every student's page. It now counts the hints the user revealed; the
  per-contest variant counts reveals made inside the contest window.
  (rev 2122)
- **Judge job queue: index on `jobs.status`.** The judge polls the `jobs`
  table on `status` several times a second per grader and claims work with
  `FOR UPDATE SKIP LOCKED`, but the table had no index on that column: every
  poll was a full scan and, under MySQL's default isolation, every claim
  locked every row it scanned, so a second grader claiming at the same
  moment got nothing and idled until its next tick, and new job inserts
  waited behind it. Measured on a 33k-row copy: idle poll 2.3 ms → 0.15 ms,
  claim 13.9 ms → 2.7 ms, empty concurrent claims 353 of 1,200 → 0; insert
  and status-update cost unchanged. New index `(status, priority DESC, id)`,
  an online DDL that took 100 ms at 33k rows and 443 ms at 200k. (rev 2115)
- **Viva: a double-click on Send or End no longer queues two grade jobs.**
  The answer and finish actions checked the session's state and then acted
  on it without a row lock, so two requests arriving together — a
  double-click, a second tab, a browser retry — could both force-finish one
  interview: two closing turns in the transcript and two grading calls to
  the model (same grade, one wasted call). Below the turn cap the same gap
  could record an answer twice. Both actions now take a row lock on the
  submission and re-read its state before acting; the late request is
  refused like any other post after the interview has ended. (rev 2114)
- **AI assist on a problem without a statement PDF sent a `null` content
  part**, which the provider rejects (400) and the student saw as "Assistant
  Error". The part is now omitted. Latent so far: every tagged problem on
  production has a PDF. (rev 2086)
- **A failed AI-assist request was marked twice**: the service recorded the
  failure, then the job relabelled it "Assistant Error (retries exhausted)"
  and appended a second error block even when nothing had been retried. The
  job now leaves a comment the service already marked alone. (rev 2086)
- **Best-score report could show a negative score.** `final_score` was
  `LEAST(max score, 100 − assist cost − hint cost)` with no lower bound, so a
  student who bought more AI assists than a problem is worth went below zero
  (worst case on production: 46 requests on one problem, −360). It is now
  floored at 0. (rev 2085)
- **AI-assist picker addressed the model by position.** The "Get" link
  carried the model's index into the provider map, so a reordered or trimmed
  `config/llm.yml` silently repointed every existing link at a different
  model, and a stale index raised a 500. The picker is now a form that POSTs
  the model by name; an unregistered name is refused with a toast (422). The
  penalty quoted in the confirmation dialog comes from the serving class's
  `ASSIST_COST` instead of a hard-coded 10. (rev 2084)
- **Viva transcript swallowed C++ template brackets.** A student who typed
  `vector<int> v;` saw `vector v;` in their own chat history (the stored turn
  was intact): student, system and error turns went through Rails
  `simple_format`, whose default sanitizer strips unknown tags such as `<int>`
  (and turned `a<b && c>d` into a bold element), and interviewer turns went
  through Redcarpet with `filter_html`, which drops them too. Plain-text turns
  now escape first and only then get paragraphs and line breaks; markdown
  turns (and the markdown editor preview) show raw HTML as visible text
  instead of removing it. `<` and `>` display exactly as typed in every role.
  (rev 2078)
- **Every submission failed with an internal grading error on servers running
  rev 2045 or later** (all chula_cp deploy hosts, 2026-08-30 14:37 local onward). Rev 2045
  cleared a stale `stdout.txt` inside the shared `prepare_testcase_directory`
  helper, which the checker re-runs *after* the program has produced its
  output — so the output was deleted between the run and the compare and every
  testcase ended in `grader_error`. The stale-output cleanup now lives in
  `Evaluator#clear_stale_output`, called once immediately before the run; the
  shared helper is create-only again. Submissions graded during the window
  carry `grader_error` and need a rejudge. (rev 2061)
- **Grading jobs stranded forever when a grader died mid-job.** A judge job
  moves to `:process` when a grader claims it and leaves that state only when
  the grader reports back, so a grader killed in between — OOM, `kill -9`, a
  host reboot, the watchdog's stalled-KILL branch — left the job, its parent
  chain, and the student's submission stuck in "evaluating" with nothing to
  move them. Nothing reclaimed them: the prod-copy development database held
  **126 such jobs, the oldest 564 days old**, from a worker that died in one
  event. `Job.reclaim_orphaned!` now returns them to the queue, from two
  places: `Grader.watchdog` sweeps the boxes its own `ps` check just proved
  have no process running (evidence, not a timeout, so a slow grader is never
  interrupted — reclaimed within a minute), and a new `grader_job_reclaim`
  recurring task sweeps fleet-wide every 10 minutes for jobs idle over 30
  minutes, covering the case the first path structurally cannot: a host whose
  watchdog is not running either. **Operators, note the one-time effect of the
  first production sweep:** a job is *not* requeued when its submission has
  already reached a final state, when it has been stuck over 24 hours, or after
  three reclaims — re-running those would overwrite grades that were settled by
  hand long ago — so the historical backlog surfaces as error jobs on the
  Grader Processes page instead, clearable there in one click. A submission
  still genuinely mid-flight is marked `grader_error`, which stops the endless
  "evaluating" and puts it on the normal Rejudge path. `GraderProcess` rows now
  also record the grader's `pid` and `host`, which the columns had always had
  room for and nothing ever wrote. (rev 2060)
- Problem statistics page: a problem with no submissions rendered the literal
  `0/0 (NaN%)` in the General Info card — the solved percentage divided by a
  zero attempt count, and Ruby yields NaN there rather than raising
  (`NaN.round(1)` returns NaN, so nothing surfaced it). It now reads
  "No submissions yet". (rev 2056)
- Viva grading: a grader reply that is not a grade — prose, an unparseable
  brace block, or JSON without a numeric `total_points` / non-empty `rubric` —
  can no longer land as a silent zero (`points: nil`, status *done*). The
  grader now re-asks the model once, then the submission goes to *Grader
  error* with the raw reply preserved for the admin and the Re-run picker
  (rev 2043).
- Judge workers: `Grader.watchdog` no longer lets duplicate graders live on
  one isolate box. It now runs under a host-wide lock (a second watchdog in
  the same minute skips instead of racing), detects more than one grader per
  box and TERMs every extra but the oldest, and stops *all* processes of a
  disabled box instead of only the first. Duplicates came from two orphaned
  `whenever` crontab blocks and turned every concurrent evaluation into a
  `!` grader error (2026-08-27 incident); the deploy pipeline now gives
  whenever a stable identifier so a path rename cannot orphan a block again
  (rev 2045; automation repo rev 58).
- Judge workers: a rejudge landing on a different isolate box than the run
  that died there no longer fails with `open("/output/stdout.txt")` — the
  evaluator removes the previous run's `stdout.txt` before each testcase
  (rev 2045).
- Judge workers / deploy: graders spawned by `Grader.watchdog` (and so by
  `Grader.restart`) no longer inherit stray file descriptors from the process
  that spawned them — they now get `/dev/null` on stdin, the per-box log on
  stdout/stderr and nothing else (`close_others`). Previously they inherited
  the spawner's non-CLOEXEC mysql2 socket and fd 6, which RVM's login-shell
  profile leaves open as a copy of stderr. Under the deploy pipeline that fd
  is sshd's stderr pipe, so every `deploy_production` job hung after
  "Successfully deployed" until the job timeout while the graders held the
  channel open (2026-08-30, all hosts) (rev 2053).

### Security
- **Anyone logged in could buy AI assistance on any submission, charging its
  owner.** The submission-assist request checked the site switch, the
  contest `allow_llm` flag and the `llm_prompt` tag, but never who was
  asking: any logged-in user could POST it against any submission id (they
  are sequential), creating the request under their own name while the
  10-point penalty landed on the submission's owner and the model call was
  billed to the deployment — on a submission the requester could not even
  open. The request is now accepted only from the submission's owner (who
  must also be able to view it) or an admin; anyone else gets a "your own
  submissions only" toast and a 403. Production history holds 11 requests
  whose requester was not the owner. (rev 2084)
- **AI-assist answers were rendered as raw HTML.** The model-written body
  went through the markdown renderer with HTML passthrough, so markup the
  model echoed from student code (a comment, a string literal) ran in the
  browser of whoever opened the comment — staff included. The body is now
  sanitized after rendering; headings, lists, code blocks and the
  server-written error block display as before. (rev 2084)
- **Admin DataTables rendered user-supplied text as HTML (stored XSS).**
  DataTables writes cell data with innerHTML, and every plain
  `{data: 'full_name'}` column in the JSON-fed admin tables — contest and
  group membership, the user list and role lists, the activity, submission,
  login and hall-of-fame reports, the scoreboard — rendered whatever markup
  the value carried; several custom renderers interpolated names raw as well.
  A self-registered user sets their own full name, and the login-failure
  report shows the raw string an anonymous visitor typed as a login, so an
  `<img onerror=…>` there ran in the browser of the admin viewing the table
  (verified on the contest manage page). Every JSON-fed table now passes its
  columns through `cafe.dt.escape_columns_by_default`, which gives each plain
  column DataTables' escaping text renderer, and the custom renderers escape
  their free-text fields; a value like `James <b>Bond</b>` now displays as
  exactly that text. DOM-sourced tables (main list, submissions, stat pages)
  are unchanged. (rev 2079)

## [4.5.0] — 2026-08-28

**Upgrade notes.** Run `bin/rails db:migrate` — this release carries 11
migrations (grounding materials + backfill from tags, viva Phase 1 fields,
`viva_daily_limit` replacing `viva_mode`, `submissions.updated_at` and
`repaired_from_id`, `submission_repairs`, `logins.success`/`attempted_login`).
Behaviour changes worth knowing before upgrading a live server: the JSON API
now enforces the login IP whitelist and single-user lockdown exactly like the
web (tokens issued before a lockdown stop working); failed logins are throttled
per IP and per account across web and API; a *disabled* group membership no
longer confers editor/reporter rights; the viva practice/exam toggle is gone
(context-based policy), `viva_grounding` tags are retired in favour of
Grounding materials, and legacy `llm_prompt` examiner tags should be migrated
with `viva:migrate_prompt_tags`. Viva submissions graded before this release carry
the LLM narrative in `grader_comment`; rewrite them with
`viva:clean_grader_comments` (report first, then `APPLY=1`).

### Added

- **Markdown editor with preview for the long prompt fields** — the viva
  Examiner briefing and Scenario (problem form), the `viva_conduct` / AI-helper
  tag prompt, and the grounding-material body are now edited in an Ace editor
  with markdown highlighting and soft wrap, with an Edit / Preview toggle. The
  preview is rendered server-side (`POST /markdown/preview`, editors only)
  through the app's own markdown renderer, tables included, so rubric tables
  and headings can be checked without saving. The plain textarea remains the
  form field underneath — saving, validation errors and the grounding "Copy
  draft into Body" button behave as before. (rev 2030)

- **"Score report" button on the problem statistics page** — `/problems/:id/stat`
  now links straight into the Best Score report with the problem preselected
  and a user group pre-picked, so the table loads with that section's scores
  on arrival: the current (non-archived) section if its students have
  submitted the problem, otherwise the cohort that actually used it (archived
  sections included), otherwise the newest live group. Switch the group there
  to compare sections. Shown to everyone who can open the stat page (admins
  and group editors). (rev 2029)

- **Viva kit importer carries grounding materials** — `manifest.yml` accepts a
  `grounding:` list (title, markdown file, optional description, attach list);
  `bin/rails viva:import` upserts each `GroundingMaterial` by title and attaches
  it to the named problems (add-only — hand-attached materials survive
  re-import; naming a problem outside the manifest fails the import). Shared
  reference text now deploys with the kit instead of being pasted into
  Manage → Grounding per server. (rev 2027)

- **Viva kit importer** — `bin/rails viva:import DIR=… [APPLY=1]` creates or
  updates `viva_exam` problems and the shared `viva_conduct` tag from a
  course-prep kit manifest; idempotent and report-first (without `APPLY=1` it
  only prints the plan). (rev 1989)

- **Hosted AI-gateway LLM provider** — a new generic provider family
  (`Llm::AiGatewayTransport` + per-role `*AiGatewayAssist` subclasses for
  comment assist, viva turns, viva grading, grounding extraction, and
  submission repair) speaks to any bearer-key OpenAI-compatible gateway (a
  LiteLLM proxy, OpenRouter, …). Everything deployment-specific is config:
  endpoint/roster/defaults in `config/llm.yml` (`ai_gateway:`, blank by
  default), the API key in Rails credentials (`llm.ai_gateway.api_key`).
  PDF attachments are rewritten to the OpenAI `file` content-part shape the
  gateways require, and per-call cost is taken from the gateway's own
  `x-litellm-response-cost` accounting header. (revs 2018–2019)

- **Abandoned viva sessions are finalized automatically** — a new hourly
  Solid Queue recurring task (`viva_session_reaper`, production only) grades
  sessions idle for 24+ hours that have at least one student answer, and
  archives greeting-only ones. Previously a student who closed the tab
  mid-interview was never graded. (rev 2016)

- **"End interview & get graded" button on viva sessions** — the owner of an
  active practice viva can finalize it early and be graded on the transcript
  so far (topics never reached score zero; the confirm dialog says so).
  Contest-only vivas (`viva_daily_limit: 0`) do not offer it. Previously a
  student who stopped answering left the session parked ungraded forever.
  (rev 2014)

- **Failed-attempts tab on the Login report** — the Logins report
  (Report → Login) gains a third tab listing failed password attempts (web
  and API) in the selected date range: attempted login string, matched user
  (when the account exists), time with seconds, and source IP. The user/group
  filter deliberately does not apply — most failures match no user. Data
  comes from the failure rows recorded since rev 2002. (rev 2003)

- **Viva grounding: one-click PDF→markdown extraction** — produces a review-first draft (the author copies/edits it into the body; once saved, body text replaces per-turn PDF re-sending). (revs 1919–1920)
- **Viva alert-review admin page** (Graders → Viva alerts) — lists flagged sessions with the triggering student utterance; the jailbreak-calibration instrument for the practice month. (rev 1917)
- **Viva Phase 1 groundwork** — examiner briefing (`viva_prompt`), turn caps, and per-turn jailbreak-alert flags: schema + model, from the 2026-07-20 deployment-readiness design. (revs 1878–1890)
- **Viva retakes** — students restart their own viva session (archives the old one, subject to the daily start limit); admin archive-and-retake remains available for any viva. (rev 1886)
- **`viva:migrate_prompt_tags` rake task** (report-first, `APPLY=1` to execute) — migrates legacy per-problem `llm_prompt` tags into `viva_prompt` and shared ones to `viva_conduct`. (revs 1880–1881)
- **Viva turn caps** — per-problem soft cap (examiner pacing instruction, default 10) and hard cap (force-finish + grade, default 15). (rev 1884)
- **`problems:replay_validate` rake task** — validates the problem import/export
  path by re-importing a problem and replaying a stratified sample of its
  submissions through the grader, diffing per-testcase results against the
  originals' stored grades (only `T→P`/`x→P` treated as benign). Dev diagnostic;
  self-cleaning, with `problems:replay_purge` as a backstop.
- **Problem import warns when a `group_min` group has mixed testcase
  weights** — group-min scoring uses one weight per group (the minimum);
  heterogeneous weights inside a group are an authoring error.
- **Dataset editor also warns about mixed `group_min` weights** — the same
  check now runs live on the Testcases tab (shared `Dataset#mixed_weight_groups`):
  a banner lists each offending group with its weights and effective (minimum)
  weight, and a per-row marker flags the affected testcases. Only shown under
  Group Min scoring.
- **Testcase config accepts CMS-style codename regexps** — the weight/group tool
  now takes `[[weight, "1-.*"], [weight, "2-.*"]]`, grouping testcases by a
  regexp matched against `code_name` (start-anchored, mirroring CMS `re.match`),
  alongside the existing `[weight, count]` form. The box gains inline examples
  and a "Syntax & CMS notes" help drawer; the full grammar and how it differs
  from CMS `GroupMin` parameters (normalized weights vs absolute points) are
  documented in `doc/dataset-scoring-and-evaluation.md`.
- **Multi-dataset problem export/import** — a problem's non-live datasets can now
  be included in its export archive ("Download (all datasets)" on the problem
  page, `Problem#export(all_datasets: true)`, or `rails "problems:export[name,all]"`),
  and are re-imported as additional (non-live) datasets. The zip format is a
  backward-compatible superset: old archives import unchanged, and the default
  "live dataset only" export is structurally compatible with previous versions
  (same files; imports identically).
- **Grounding materials: a dedicated model + admin library** (Manage → Grounding)
  for viva reference material, replacing `viva_grounding` tags. Files are sent
  to the interviewer/grader as PDF `image_url` parts; the library shows a
  per-item token estimate and problem-reuse count.
- **Near-Miss Grading (batch instrument)**: `rake near_miss:repair` runs bounded
  LLM repair over a contest's failing submissions (deterministic budget gate;
  accepted fixes graded by the normal judge as student-invisible shadow
  submissions linked via `submissions.repaired_from_id`), and
  `rake near_miss:report` produces rescue-rate / mechanical-gap / budget-compliance
  analysis. Spec: `docs/superpowers/specs/2026-07-30-near-miss-grading-design.md`. (revs 1928–1937)
- **Self-hosted LLM provider**: generic OpenAI-compatible transport
  (`Llm::SelfHostChat`, configured via `self_hosted_models:` in `config/llm.yml`)
  with a submission-assist provider (`Llm::SelfHostAssist`) and the Near-Miss
  repair provider. Model identity is config data; no credentials (intranet). (revs 1928–1937)
- **Near-Miss run browser** (Report → Near-Miss Runs, admin-only): web report
  over repair batch runs — run list with outcome/token/cost rollups, per-problem
  rescue-rate / mechanical-gap / budget-compliance tables (multiple runs render
  side by side for budget and model comparisons), and per-attempt drill-down
  showing the measured patch, rounds log, category, tokens/cost, and links to
  the original and shadow submissions. (rev 1949)
- **CMS task clone** — `rails "cms:clone[task]"` imports a Batch task (all datasets)
  straight from a live CMS server over ssh — official dump subtree + selective
  blob fetch on the server, converted to the cafe package layout and imported
  through the trusted importer. GroupMin (count and regex forms) maps to
  `group_min`; Communication/OutputOnly, file-I/O, and GroupMinPrereq tasks are
  rejected with clear messages (per-dataset skip when non-active). Connection
  settings live in `config/cms_remote.yml` (gitignored; sample committed). (revs 1960–1965)
- **`cms_comparator` evaluation type**: user checker invoked with CMS's own
  argv order (`input, correct, user`), distinct from the legacy `custom_cms`
  order (`input, user, correct`) that existing cafe problems depend on;
  `Converters::CmsDumpConverter` now maps CMS's `comparator` evaluation mode to
  it, unblocking correct import/grading of checker-based CMS comparator tasks.

### Changed

- **Viva grading no longer copies the LLM narrative into `grader_comment`**
  (rev 2036). A graded viva now carries the compact marker `viva` — or
  `viva:terminated` when the interview was force-ended — in
  `submissions.grader_comment`, the per-testcase verdict field that the stat
  tables, the Submission report's Result column, the grader monitor and the
  API's `last_result` / `grader_comment` print inline. The narrative itself
  is unchanged and still lives on `viva_grades.narrative`, rendered by the
  grade card on the viva page. Existing rows: `bin/rails
  viva:clean_grader_comments` (report-only; `APPLY=1` to rewrite) — only
  `done` rows whose `grader_comment` contains their narrative are touched;
  error text is left alone.

- **Viva problem edit page uses both columns** — for viva problems the
  (empty) Dataset half of `/problems/:id/edit` becomes a "Viva Exam" card
  holding the Scenario, the Examiner briefing and the interview setup
  (grounding materials, conduct profile, turn caps, daily start limit) at full
  width, while the Detail card keeps the general settings; both cards are one
  form. The Description and Hint tabs are dropped for viva problems (the
  scenario lives in the card; hints are a code-submission feature), and
  switching a problem to or from viva now redraws the layout on save. Regular
  problems are unchanged. (rev 2031)

- **Viva prompts hardened for provider robustness** — the grading transcript
  now uses `INTERVIEWER:`/`STUDENT:` labels and ends with an explicit
  "END OF TRANSCRIPT — output only the grade JSON" re-anchor (with wire-role
  labels and no re-anchor, Claude models kept interviewing instead of grading
  in 21/24 bake-off calls; 16/16 compliant after); the `[[VIVA_DONE]]` token
  is now binding (a model may never announce the interview's end without it);
  and interviewer turns are instructed to use plain Markdown only (no LaTeX —
  `safe_markdown` renders `$...$` as raw symbols). (rev 2024)

- **Viva daily start limit counts engaged sessions only** — a start consumes
  one of the day's slots once the student sends their first answer;
  greeting-only sessions (opened, never engaged — 39% of starts in the first
  student trial) no longer burn the budget. (rev 2014)
- **Viva integrity alerts narrowed to real subversion** — off-topic chat,
  frustration, break requests, and asking to skip or stop no longer raise
  `[[VIVA_ALERT]]` (they get a one-sentence redirect instead); the alert
  triggers now cover role spoofing, score/answer extraction, question
  laundering, and credit negotiation. Cuts the practice-log noise and, under
  the future exam policy, stops benign behavior from drawing warnings.
  (rev 2014)

- **Submit authorization now flows through one predicate**
  (`User#can_submit_to_problem?`): the web submit, the JSON API, viva start,
  the submit-form UI, and the model-layer validation all share the same gate.
  An editor's test-submit right on draft/hidden problems in their own groups —
  previously web-only — now also applies to the API and to starting a viva
  (intended design: viva authorization matches normal problems). (rev 1996)
- **Viva examiner prompt lives on the problem** (`viva_prompt`, audited/redacted), layered with optional shared `viva_conduct` tags in a fixed order; `llm_prompt` tags are again exclusively the AI-helper's namespace. (rev 1879)
- **Viva grounding is now attached to problems via a viva-only "Grounding
  materials" selector** (with a per-problem token total) instead of the mixed
  Tags dropdown; the `viva_grounding` Tag kind is retired and existing tags
  backfilled.
- **Viva jailbreak handling is detect-only** — the examiner stays in character and only *detects*; the backend applies policy: flags are logged and a notice is shown to the student, never terminating the interview (was: immediate termination on any detection). The warn-then-terminate machinery stays in the codebase, dormant, for the Phase B per-contest policy. (rev 1882)
- **Viva authoring surface** — a viva problem's description is its "Scenario (markdown)" (sent verbatim to the examiner; side-PDF generation disabled), edited together with the examiner briefing, conduct profile and turn caps in the problem form; only `viva_conduct` tags are hidden from the generic tag picker (they have their own Conduct-profile select) — `llm_prompt` tags stay there since it is the only UI that attaches them (to the AI-helper) and they can never be public. (revs 1887–1888, 1900)
- **Viva: practice/exam mode replaced by context-based policy** — every viva is practice outside contests, limited by a per-problem daily start limit (blank = site default, 0 = contest-only); exam strictness returns as per-contest retake budgets in Phase B.
- **Near-Miss LLM-call hardening** — the self-host transport allows 600s reads
  (16384-token reasoning generations legitimately exceed the stock 300s); a
  round truncated at `max_tokens` with empty content now fails the attempt
  immediately with a "raise max_tokens" remark instead of burning retry
  rounds; compile-error verdicts no longer decode the literal "Compilation
  error" string into nonsense per-testcase lines. (rev 1954)

### Fixed

- **Student main list rendered the whole viva narrative as a paragraph**
  (rev 2036) inside the "Latest Results" cell — the `[…]` verdict span, built
  for a 10–50-char `P-Tx…` string, wrapped 300–450 chars of feedback. Viva
  rows now show the score plus a badge (`viva`, or red `terminated`) that
  links to the viva page, without the per-testcase evaluations icon and
  compiler-message link that don't apply to a viva. Ungraded viva rows say
  "Interview in progress" / "Grading in progress…" instead of "Waiting to be
  graded…", and a failed grading (`grader_error`, which never sets
  `graded_at`) shows a red "Grader error" badge linking to the viva page
  instead of waiting forever.

- **Report filters can be prefilled from the URL** — the Problems / Users
  filter cards shared by the Best Score, Submission, Activity and AI reports
  read their preselection from parameter names Rails never produces
  (`params[:'probs[ids][]']`, `params[:group_id]`), so a link such as
  `/report/max_score?probs[use]=ids&probs[ids][]=42` always rendered an empty
  form. They now honour `probs[use|ids|group_ids|tag_ids]` and
  `users[use|group_ids]`, falling back to the old defaults on missing or
  malformed values. (rev 2029)

- **Viva grading model no longer depends on how the interview ended** —
  the done-sentinel path passed the interview model into
  `Llm::VivaGradeAssistJob` while the hard-cap path used the grade
  service's default, so one cohort could be graded by two different
  models. Both paths now use the grade service's default; only the admin
  "Re-run grading" picker passes an explicit model. (rev 2011)

- **Viva LLM completion caps raised** (grade 2048→8192 tokens, turn
  2048→4096) — reasoning models spent 2–3k tokens before the grade JSON and
  truncated it (`finish_reason=length` → `grader_error`) on a 13-turn practice
  viva. (rev 1990)

- **Problems manage page: viva rows offer Start Viva / View Viva** instead of
  the code-editor Submit button, which bounced viva problems to the main list
  — a dead end for a student-hidden viva (in-group switch off), since the
  student-scoped main list never shows it. Together with the editor
  test-start right (rev 1996) this makes hidden vivas actually startable by
  the group's editors and admins. (rev 2000)
- **Model-layer submit-authorization validation was a silent no-op since the
  Rails 6.1 era** — `Submission#must_have_valid_problem` refused via
  `errors[:base] <<`, which registers nothing on modern Rails, and skipped
  binary submissions entirely (`return if source==nil`). Resurrected with
  `errors.add` on the shared submit gate; trusted server-side tooling (repair
  shadows, replay engines, model-solution import) bypasses explicitly with
  `save!(validate: false)`. (rev 1996)
- **Reporters no longer get a submit form they can't use** — on a problem
  hidden from students (in-group switch off) a reporter can view the problem
  but not submit; the editor page now renders view-only with a notice instead
  of a Submit button that always failed after the fact. (rev 1996)
- **Near-Miss report: ungradeable shadows are no longer counted as 0-point
  grades** — accepted attempts whose shadow has no real judge outcome
  (`grader_error`, or still in flight) are excluded from gap/rescue statistics
  and surfaced as an explicit `ungradeable` count in the rake report, CSV, and
  run browser (a judging-infrastructure failure previously read as mass
  negative gaps — the void a68_final lesson). (rev 1953)
- **Viva smoke-test UX fixes** — archive refreshes the page; viva submissions no longer open the code editor (evaluations/download/compiler_msg included); students see the retake policy and their remaining daily starts. (revs 1899, 1901)
- **"Import testcases" is stricter and no longer crashes on errors** — replacing
  into a dataset that no longer exists now shows an error toast instead of
  silently creating a new dataset; the testcases-only flow no longer overwrites
  the problem's public attachment when the uploaded zip contains an
  `attachment/` directory; and all import-testcases error paths surface as a
  toast (they previously raised a template error by re-rendering the standalone
  import page).
- **Problem import: `code_name_regex` now actually applies** — the custom
  code-name extraction regex accepted by `ProblemImporter` was parsed but its
  result discarded; testcase code names always fell back to the raw wildcard
  match.
- **Problem import: model solutions survive round-trips** — imported model
  solutions had garbled source filenames (`cpp_fibo.cpp` → `p_fibo.cpp`), were
  not tagged as model solutions (so the *next* export silently dropped them),
  and were attributed to an arbitrary user; they are now split on the first
  `_`, tagged `:model`, and owned by the importing user.
- **Problem import: empty "Full name" no longer blanks the title** — it now
  falls back to the short name (a `config.yml` `full_name` still wins).
- **Problem export now round-trips everything the author created** — the
  markdown description, `markdown` flag, `score_param`, and dataset data
  files were silently dropped by export (or never imported); an exported zip
  re-imports field-identical. `ProblemExporter.dump_problems` (console bulk
  export) no longer crashes on a typo'd default, and the exported statement
  is named `statement.pdf` (was `statment.pdf`).
- **Downloading the archive of a problem with no live dataset** shows an
  alert instead of a 500 error page.
- **Grounding material PDF/image attachments no longer crash the LLM
  request builder** — `GroundingMaterial#grounding_file_parts` iterates raw
  `ActiveStorage::Attachment` records (from a `has_many_attached` collection),
  which don't respond to `#attached?`; `Llm::Request.encode_pdf_part` was
  unconditionally calling it, so any viva turn/grade request for a problem
  with an attached grounding file raised `NoMethodError` instead of sending
  the file.
- **Viva submissions handled correctly by bulk dataset rejudge, hall of fame, the admin testcases API and the grader backlog** (the API description leak is listed under Security). (rev 1907)
- **Viva sessions stuck in "evaluating"** after a worker crash are swept to `grader_error` (regradable) and surfaced on the graders monitoring page. (rev 1909)

### Security

- **API now enforces the login IP whitelist** (rev 2026) — `right.whitelist_ip`
  restricted web sessions but not the JSON API: a JWT obtained inside the
  whitelisted network (or before the whitelist was switched on) kept working
  from anywhere, e.g. from home during an on-site lab exam. The whitelist is
  now re-checked on every `/api/v1` request and enforced at `auth/login`
  (no token issued), with the same exemptions as the web gate: admins,
  `right.whitelist_ignore`, and users with edit rights on any problem. Both
  doors share one predicate, `User#allowed_from_ip?`, backed by
  `GraderConfiguration.whitelisted_ip?` for the CIDR matching; the
  route-enumerating sweep spec asserts the gate on every endpoint.
- **Login brute-force throttling, pooled across the web form and the API** —
  failed password attempts are counted per client IP and per attempted
  account (30 failures within a sliding 3-minute window, sized well above
  real frustrated-student retry bursts at exam starts); once a budget is
  exhausted, further attempts are refused before any password check — web
  gets a redirect with an alert, the API its existing 429 — until the window
  drains. Both doors draw down the same counters, replacing the API's old
  per-controller `rate_limit` (which an attacker could sidestep by splitting
  attempts across doors, and which counted successful logins too). Failed
  attempts are now also recorded in `logins` (`success` flag +
  `attempted_login` column, migration required); login/cheat reports and the
  heartbeat user lookup were scoped to successful logins so failures don't
  pollute multi-IP cheat detection. A successful login clears the account
  counter (proof of ownership) but deliberately not the IP counter. No
  permanent per-account lockout on purpose: that would let anyone lock a
  victim out of an exam by hammering their login name. (rev 2002)
- **A disabled group membership row now revokes editor/reporter problem
  access** — previously a membership with `enabled=false` still conferred the
  editor's full problem-level powers (view, edit, test-submit, rejudge) and a
  reporter's view access; a disabled membership now grants no role at all,
  matching members (intended design: disabled editor IS NOT an editor).
  (rev 1996)
- **Problem import/export no longer builds shell strings** — unzip/zip run
  with argv-style exec (a hostile problem name could previously inject shell
  syntax), extraction directories are derived via `parameterize`, and a
  containment check rejects archives whose entries or symlinks escape the
  extraction directory (zip-slip).
- **Importing a problem under an existing name now requires edit rights on
  that problem** — previously any group editor could silently overwrite any
  problem in the system by importing a zip with the same short name. Admin
  re-import-to-update behavior is unchanged.
- **Viva: transcript/grade pages now enforce submission-view authorization**
  (were open to any logged-in user) — archived viva attempts are visible
  only to their owner and staff.
- **API `GET /api/v1/problems/:id/description` no longer leaks the viva
  interview scenario to students** — the description IS the hidden scenario
  for viva problems; the endpoint was missing the same `can_view_problem_pdf?`
  gate the sibling PDF endpoint already enforced.
- **API now honors single-user (lockdown) mode** (rev 1992) — enabling
  `system.single_user_mode` blocked web sessions but not the JSON API: a JWT
  obtained beforehand kept submitting, and `auth/login` even issued fresh
  tokens (exploited on 2026-08-19 during a pre-quiz lockdown; submissions
  934223–934226 on the algo grader). Non-admins are now rejected per-request
  and at login while the mode is on, and tokens issued before the last
  lockdown (`min_last_login_time`, bumped when the mode is switched on) are
  retroactively invalid — the API parallel of the web session kill. A new
  route-enumerating sweep spec asserts the no-token and lockdown gates on
  every `/api/v1` endpoint, so future endpoints are covered automatically.

## [4.4.2] — 2026-07-01

### Fixed

- **Report filters: user-group dropdown now respects reporter scope** — on the
  report filter pages (Best Score / Submissions / User Activity / AI Assist),
  the "Only users from this group" dropdown listed **every** group in the
  system for non-admins; it now lists only the groups the user can report on
  (`@groups`), matching the problem-group dropdown. No user data leaked (results
  were already intersected with `reportable_users`), but group names no longer
  do. The `login` analytics report now sets `@groups` so its user filter renders.

### Added

- **Role-aware scope help on the report pages** — each report filter page (Best
  Score / Submissions / User Activity / AI Assist) now shows an always-visible
  line stating what *you* can see (Admin: everything; Editor: full access incl.
  archived, listing your courses; Reporter: live courses only), with a
  "What you can see" drawer detailing every course you edit/report on and the
  three visibility switches. Answers "who can see what?" at the point of use.
- **Empty-report explanation for reporters** — a non-admin reporter whose
  problems are all unavailable or whose group is archived (disabled) reaches the
  report screen but sees no data (by design — `available` is an absolute
  student-exposure switch only admins bypass). The report filter pages now show
  an info notice counting the hidden problems and explaining why, instead of a
  silent empty table.

### Changed

- **Group editors are now content curators of their groups** — an editor can
  see, edit, and report on **every** problem in a group they edit, regardless of
  the problem's `available` flag or whether the group itself is disabled
  (archived). Previously the editor scope required `available: true` **and** an
  enabled group, so editors were locked out of their own draft (unavailable)
  problems and of any finished/archived course exactly like students — only an
  admin could get in. Reporters are unchanged: they remain scoped to available
  problems in enabled groups, and editor visibility stays a strict superset of
  reporter visibility. **Operational note:** to give a non-admin access to a
  finished/archived course, make them an **editor** of its group (a reporter
  still sees only live courses).
- **Report filters are archive-aware** — the group dropdowns now list an
  archived (disabled) group only for users who can still report on it (its
  editors), and mark it with an "archived" pill; reporters no longer see
  archived groups as dead-end filter options, and a reporter left with no live
  groups is turned away at the report gate instead of shown a blank screen.
- **Config templates pruned and made consistent** — `config/application.rb`
  is now tracked directly (it was ignored behind a byte-identical sample); the
  redundant `llm.yml` / `cafe_grader.rb` `.SAMPLE` files and the dead 2016-era
  `abstract_mysql2_adapter.rb.SAMPLE` were removed (the real configs are
  tracked and secret-free), and the identifiers in `credentials.yml.SAMPLE`
  were scrubbed. Fresh clones now boot without hand-copying samples (rev 1769).

## [4.4.1] — 2026-06-13

### Added

- **Per-user activity summary report** — one row per user over a
  time / submission-id range × problem set: submission count, problems
  tried, problems solved (raw_sum-scored datasets excluded — they have
  no defined full score), first/last submission, and distinct IPs.
  Optionally lists zero-activity users for the selected filter
  (highlighted, off by default). Runs as a single `GROUP BY` pass over
  submissions without touching the scoring engine, so even an
  all-problems window stays fast (rev 1758).

### Changed

- **Profile page redesigned** as a two-column identity card + settings
  layout — left: initials avatar, name, login badge, read-only
  email / default language / member-since; right: a Preferences card and
  a Change-password card. Controller and permitted params unchanged
  (rev 1763).
- **Per-problem "my submissions" table** restyled into the carded,
  hover/condensed UI used elsewhere, with real empty states, a `#id`
  link, filename-as-download with a language badge, a compact AI-assist
  badge, and an icon-only Edit button (rev 1764).
- **Grader-processes "Recent Submissions" card** gains a whitelisted
  `?limit=` toggle (20 / 100 / 500, default 20); Refresh and the
  10-minute auto-refresh preserve the chosen limit (rev 1761).
- **Footer slimmed** from a ~41px bar to a ~30px centered watermark —
  coffee mark, cafe-grader wordmark linking to GitHub, and a monospace
  `rev X.Y.Z` (rev 1762).
- **Updated-announcement cards** keep their shadow instead of going
  flat; the "updated" state now adds a 50%-opacity red border on top of
  the standard `shadow-sm` rather than replacing it (rev 1760).

## [4.4.0] — 2026-06-11

### Added

- **Management (write) API** under `/api/v1/` — the API is no longer
  read-only. All endpoints reuse the model-layer authorization
  (`can_edit_problem?`, group-editor scope, admin role) and write
  attributed audit rows:
  - **Problems**: `POST /problems` (creates the default dataset and live
    pointer atomically), `PATCH`/`DELETE /problems/{id}`,
    `PUT /problems/{id}/statement` (PDF upload).
  - **Datasets**: list/create under the problem,
    `PATCH /datasets/{id}` (settings), `DELETE` (refused for the live or
    last dataset), `POST /datasets/{id}/set_live`,
    `POST /datasets/{id}/files` + `DELETE /datasets/{id}/files/{attachment_id}`
    (checker / managers / data files / initializers).
  - **Testcases**: `POST /datasets/{id}/testcases` (file upload or plain
    text, CRLF-normalized), `PATCH`/`DELETE /testcases/{id}`, and
    `POST /problems/{id}/testcases/import` — bulk zip import through
    `ProblemImporter` with a single consolidated `import_testcases`
    audit row.
  - **Users** (admin only): paginated/filterable index, show, create,
    update (blank password = keep), delete (self-delete refused). Role
    granting stays web-only by design.
  - Every content-affecting dataset/testcase write invalidates workers'
    cached copy of the dataset (`WorkerDataset`), so judges re-download.
- **`expires_at` in the API login response** so clients know when to
  re-authenticate.
- **`bin/rails check`** — one task running every test suite plus the
  swagger freshness check (rev 1745).

### Changed

- **API token lifetime reduced from 7 days to 12 hours**
  (`Api::V1::AuthController::TOKEN_TTL`). Bearer tokens cannot be
  revoked server-side, so the TTL is the whole exposure window for a
  leaked token. Tokens issued before the deploy keep their original
  7-day expiry.
- **Submission language authority**: the problem's permitted-language
  set is now authoritative in the new-submission UI and enforced again
  at submit time (revs 1740-1741).
- **Announcement body previews render markdown** instead of stripped
  text (rev 1742).
- **Daily cleanups moved into Solid Queue's `recurring.yml`**
  (rev 1739).
- **Database collation standardized on `utf8mb4_0900_ai_ci`** across
  every table (MySQL 8 only; MariaDB unsupported), enforced by test
  (rev 1746).

### Fixed

- **`Dataset#invalidate_worker` never invalidated anything** — it
  referenced a nil instance variable, so the worker-cache delete
  matched zero rows. Also wired the (previously missing) invalidation
  into the web `testcase_delete` action: workers no longer keep grading
  against deleted testcases.
- **Dataset edit form adapts to checker/manager/main_filename state**
  (issue #48) and the score_type / evaluation_type UI now matches the
  engine semantics (revs 1737-1738).
- **API testcase endpoints de-confused `id` vs per-problem `num`**, and
  scores are emitted as JSON numbers (BigDecimal was serialized as a
  string); problem detail exposes `last_submission_id` (revs 1743-1744).

### Security

- **API login rate limiting** — 10 attempts/minute per client IP on
  `POST /api/v1/auth/login` (was unthrottled).
- **Disabled accounts are now refused API tokens and rejected
  per-request** even with a still-valid token (previously the `enabled`
  flag was only enforced by the web session flow).
- **API mutations carry audit actors** — `Current.user`/`Current.ip`
  are set for API requests, so audit rows from API writes are
  attributed instead of anonymous.
- **Viva exam hardening**: jailbreak attempts terminate the interview
  (`[[VIVA_ALERT]]` flow); answering restricted to the submission
  owner; problem PDFs hidden from students for viva problems; stuck
  assistant turns recover instead of silently hanging (revs 1722-1736).

## [4.3.3] — 2026-05-19

### Added

- **Help drawer on `/problems/:id/edit`** — a Bootstrap offcanvas panel
  opened by a labeled `? Help` button in the page header. Documents the
  Detail-card fields, dataset structure, operations, and links out to
  the project wiki. Pattern codified in `CLAUDE.md` as
  "context-dependent help" (inline knowledge cards on index/overview
  pages; offcanvas drawers on edit/detail pages).
- **`Live` badge in the dataset selector** marking the currently-live
  dataset. The `Set as live` button is shown only on non-live ones, so
  the state is never ambiguous.
- **PDF Export sub-section** on the Description tab with an explicit
  Delete button (uses a hidden-form pattern so it can't produce
  nested `<form>` tags).
- **CU pink + KU yellow-green gradient `C` favicon and navbar brand
  mark.** Single asset (`app/assets/images/icon.svg`) serves both the
  browser-tab favicon and the in-app brand mark — single source of
  truth.
- **`CHANGELOG.md`** itself (this file).
- **Dev-environment additions**: `listen` gem with
  `ActiveSupport::EventedFileUpdateChecker` replaces polling-based file
  watching (fixed multi-second WSL2 cascading-turbo-frame slowness);
  `rack-mini-profiler` + `stackprof` for in-app perf diagnostics.
- **`doc/backlog.md`** as the project's convention for tracking
  deferred design work (linked from `CLAUDE.md`).

### Changed

- **General tab of the problem editor** reorganized into 5 labeled
  sections (Identity / Statement & Files / Categorization / Visibility
  & Listing / Grading & Compilation), with `permitted_lang` moved into
  Grading & Compilation. Column split changed from 5/7 to 6/6 to give
  the form more room.
- **Description tab**: yellow info-card removed (content moved into the
  help drawer), textarea grown to 20 monospaced rows, dead `markdown`
  / `url` fields cleaned up.
- **Hint tab**: alert-wrapped selector replaced with a flat row,
  redundant labels dropped, Add/Delete separated, body field now a
  textarea, friendlier empty state.
- **Dataset selector**: alert wrapper stripped, redundant labels
  dropped, dropdown gets select2 styling, Add + Set-as-live remain
  visible while Rejudge + Delete move behind a `⋮` dropdown (per
  CLAUDE.md's Progressive Condensation rule).
- **Section headers unified** across both the problem form column AND
  the dataset card (Settings/Testcases/Files tabs) using
  `h5 fw-bold text-body-emphasis pb-2 border-bottom`.
- **`compilation_type` field** switched from a `<select>` (with an
  off-feeling blank option) to vertically-stacked styled radio buttons.
- **Server-mutating clicks across dataset views** migrated from legacy
  `link_to … data: { turbo_method: … }` to `button_to` and
  hidden-form + HTML5 `form="..."` patterns per CLAUDE.md.
- **Per-testcase row actions** redesigned as three visible icon-only
  buttons (input / output / delete) with tooltips, sharing three
  hidden forms (Flavor B); the testcase table also picks up the
  project's standard admin-table classes.
- **Per-file row actions** in the Files tab (managers / checker /
  initializers / data files) redesigned same way.
- **Grammar / wording sweep** across the problem editor: tooltip
  rewrites, confirm-dialog standardization ("Really delete X?" →
  "Delete X? This cannot be undone."), `score_type` option text
  rephrased, sentence-case consistency, etc.
- **`finance` Material Symbol replaced with `query_stats`** wherever it
  meant Statistics — clearer metaphor.
- **`llm.yml.SAMPLE` refreshed** to mirror the real config's schema,
  documentation, and environments.

### Fixed

- **AuditLog `destroy` callback** no longer raises "Auditable must
  exist" — the polymorphic `belongs_to` is now declared
  `optional: true`, matching the helper's already-correct treatment of
  destroyed records.
- **Quick-create on `/problems`** now refreshes the list. The previous
  `turbo_stream.append` of a `datatable:reload` event had no listener
  on this page; switched to a `redirect_to` with `status: :see_other`.
- **select2 dropdowns** now reliably fire `change` events into
  Stimulus. select2 v4 dispatches events through jQuery's event system,
  which doesn't always reach native `addEventListener` listeners that
  Stimulus' `data-action` relies on. A bridge in
  `init_ui_component_controller.js` listens for the jQuery
  `select2:select` event and re-dispatches it as a native `change`.
- **`simple_form_for` data-attribute collision**: passing both a
  top-level `data:` and an `html: { data: { … } }` silently dropped the
  top-level one. The dataset and hint selectors now consolidate
  everything into `html: { data: { … } }`. Footgun documented in
  `CLAUDE.md`.
- **Tooltip data-attribute encoding**: Rails' `link_to`-and-friends
  JSON-encode nested `data: { bs: { toggle: … } }` hashes (HAML
  flattens them with hyphens). Several tooltips on problem/contest/
  dataset edit pages were silently broken because the rendered attribute
  was `data-bs='{"toggle":"tooltip"}'` instead of `data-bs-toggle="tooltip"`.
  Migrated to flat `data: { bs_toggle: … }` form across the codebase.
- **WSL2 dev-mode cascading-turbo-frame slowness** (~2 s per concurrent
  request) diagnosed and fixed: the default polling
  `FileUpdateChecker` runs `Dir.glob` on every request and concurrent
  calls serialize on WSL2 inode locks. Switched to the evented variant
  (see Added).
- **`Language` model**: `name` is now enforced unique (via DB index) and
  immutable after create (via model validator). A migration
  idempotently re-runs `Language.seed`, so newly-added entries (e.g.
  `viva`) land on existing installations via `db:migrate` without a
  manual `db:seed` step. Language seed itself uses
  `find_or_create_by!` / `update!` so partial failures raise instead
  of leaving half-created rows.

### Internal

- Convention notes added to `CLAUDE.md`: flat data-attribute form for
  Bootstrap data attrs; offcanvas help-trigger labeling exception;
  context-dependent help-pattern split; backlog pointer; development
  environment (file watcher and profiler).
- Project-history memory entries added (branch workflow, simple_form
  data-collision gotcha, grep-existing-pattern-first principle).
- `doc/backlog.md` seeded with deferred items (help-pattern
  unification, AuditLog destroy test, orphan `contests/_contest_help`
  partial, drawer-content density rewrite).
