# Judge worker pool — handoff, 2026-10-04

Written at the end of the design thread so two follow-up threads can start
cold: one for the pre-phase-0 hardening fixes (§3), one for the spec revision
(§5). Read this file first in either thread.

## 1. Where things stand

- **Spec:** `docs/superpowers/specs/2026-10-04-judge-worker-pool-design.md`,
  committed on `master` as rev 2229 (not pushed). Approach B, the protocol
  worker. Status: *revision 2 committed 2026-10-08 as rev 2262; review
  round 2 pending* (review it against rev 2229: `hg diff -r 2229 -r 2262`).
- **Review round 1:** an independent session reviewed rev 2229 and raised nine
  main points plus four smaller ones. Every citation was verified against the
  code and the local prod copy of cp-grader's DB; the outcomes are in §2.
- **Fleet facts** behind the design (host sizing, traffic share, peak load,
  the 2024–25 polling root cause) are in the spec §3 and in Claude's memory
  note `cafe-grader-worker-overhaul`.
- **No pool code yet.** The three hardening fixes of §3 shipped in 4.7.2;
  phase 0 has not started.
- **Resumed 2026-11-19** after the exam pause (parked 2026-10-10). dae
  weighed a feature bookmark for the pool work and kept the rule that it
  lands on `master` in releasable slices; the spec's decision log (§15,
  2026-10-04 entry) now gives the reason. Since revision 2, `master`
  changed the grading engine in revs 2278–2286 (per-host isolate and
  compiler options in `worker.yml` written by `engine:detect`,
  `engine:langcheck`, a grader error for a language with no compiler on
  the host); review round 2 checks the spec against them (§7).

## 2. Review round 1 — verified outcomes

| # | Point | Real? | Verified by | Decision |
|---|---|---|---|---|
| 1 | Shadow jobs would write live rows; the sweep re-enqueues through `add_judge_job`, which deletes evaluations | yes, spec bug | `app/models/submission.rb` `add_judge_job` | shadow gets its own enqueue, retry and storage; compare when both results are final |
| 2 | No grading generation; rejudge during a lease lets two jobs write the same rows; scorer reads the live dataset, not the snapshot | yes | `Scorer#process` compares live testcase ids and fails with "Evaluations are missing" | job id = generation; submission stores its current job id; envelope stored on the job; score from the snapshot |
| 3 | Protocol races: heartbeat renews by job id, `seq` not scoped to attempt, complete with missing testcases, non-atomic writes, no DB uniqueness | yes | spec text; `evaluations` has no unique index | adopt all five rules; unique index on `(submission_id, testcase_id)` after a dedup migration |
| 4 | Dial-to-zero strands waiting / released `grade` jobs; reclaim sweep is 10 min / 30 min; Retry All revives everything | yes | `config/recurring.yml` `grader_job_reclaim`; `GradersController#retry_all_error_jobs` uses `update_all` | dial change converts waiting jobs; 1-minute lease sweep; Retry All current-chain-only (also a pre-phase-0 fix, §3) |
| 5 | A hung runner is renewed forever; checker and initializer have no timeout | yes | `Checker#process` `Open3.capture3`; `JudgeBase#run_initializer` `system` | per-phase deadlines in the agent; server-side ceiling per job from its cost; timeouts also a pre-phase-0 fix (§3) |
| 6 | A bad dataset pauses every worker in turn | yes, spec bug | spec §6.6 | three fault domains: job/dataset → quarantine; worker → pause everywhere; server/network → backoff; manual pause is a separate flag |
| 7 | PostgreSQL table names use bare testcase ids; checkers and initializers run on the host unsandboxed | yes, and bigger | `lib/templates/postgres/postgresql_initializer.rb`, `app/engine/compiler/postgres.rb`; `Checker#process` runs on the host as the app user. cp-grader: 35 custom-checker + 4 PostgreSQL datasets; 18 admins + 39 enabled group editors can upload a checker | namespace by server + dataset hash; sandbox checkers and initializers in phase 0 slice 0.3 (§4); **interim policy = dae's decision (§6)** |
| 8 | `Replay::ReplayDiff` ignores points | yes, dev harness only | code; `engine:smoke` (the deploy gate) does compare status, points and grading string | fix in slice 0.5 before anything relies on replay |
| 9 | Weight-first ordering starves low weights; claim threads need one shared budget; concurrency unit; memory accounting; no preemption | partly | spec §9.3 | weighted service; one scheduler owns the idle budget; concurrency in jobs with a per-job runner cap; memory from each job's limit |
| s1 | SHA-256 storage and retention | yes | Active Storage stores MD5 only; checker replace purges the old blob at once | digest table filled on attach; old blobs kept while jobs reference them |
| s2 | Claim query under capability filters | yes, and the 2024 bug in a new coat | non-index condition inside a locking read holds locks on skipped rows | two-step claim: candidate ids without locks, then lock one by primary key |
| s3 | Token rotation needs two digests and an audit action | yes | — | `previous_token_digest` + `previous_valid_until`; `rotate_token` audit action |
| s4 | Acceptance tests beyond throughput | yes | — | add lost responses, duplicate/reordered events, rejudge mid-run, shadow failure, dataset edit, server restart, rollback with waiting jobs, cold-cache latency |
| — | State-transition table before phase 0 | yes | — | server side only (generations, attempts, leases, shadow, rollback); agent states wait for the phase 2 plan |

Facts that changed during verification: the 312 duplicate evaluation pairs
cited earlier all belong to **deleted submissions** (4,279 orphan rows; the
`dependent: :destroy` on `Submission#evaluations` exists, so a bypass path
created them). They are not evidence of the rejudge race. No submission
carries "Evaluations are missing" today.

## 3. Pre-phase-0 hardening: three fixes

**Status 2026-10-08: all three shipped on master** — fix 3 rev 2251, fix 2
rev 2252, fix 1 rev 2253, released as 4.7.2. Where the code differs from the
design below (fold into spec revision 2):
- *Chain check* counts every row of the submission, not only compile rows:
  chain id = the compile job's id, or `parent_job_id` for evaluate and score
  jobs, and a chain is current when no row has a higher one. A successful
  compile row is deleted after a day (`Job.clean_old_job`) while the chain's
  error rows stay 30 days, so "no newer compile job" alone lets a superseded
  error row look current again.
- *Retry guard* also skips a job whose submission is `done` or
  `compilation_error`: a newer chain finished, and its rows may all be gone.
  (The 2026-10-07 prod copy keeps 249k successful job rows back to
  2026-09-16 — the nightly `grader_cleanup_web` seems not to have run since;
  unverified on the host.)
- *More check points:* before the compile writes the binary and status,
  and before the grader's error paths call `set_grading_error`.
- *Evaluation write* is `find_by || create_or_find_by!`, so a judge host
  deployed before the web host has migrated never creates duplicates.
- The initializer timeout relies on the `WorkerDataset` transaction rollback
  (status back to `created`) rather than deleting the row; timeouts default
  in code (`JudgeBase::CHECKER_TIMEOUT`, `INITIALIZER_TIMEOUT`), and
  `worker.yml.SAMPLE` shows the `limits:` block commented out.
- *Watchdog* kills a stuck box only when the process is also older than
  600 s, so a grader just spawned on a box with an old heartbeat survives.
- *Migration timing* (local prod copy, 7.56 M rows): 30 s end to end —
  orphan scan 3 s, duplicate scan 15 s, index build 11 s online (48
  concurrent inserts during it, slowest 25 ms). No duplicate pair on a live
  submission; the 4,279 orphans all had `submission_id` NULL.

Existing bugs (all pre-date the pool work; authorship in the thread: the
delete-without-cancel is from 2023, Retry All from 2026-04, the timeouts
missing since 2023, the watchdog gap carried through the 2026-08 rewrite).
**Design discussed, not yet approved to implement.** Ship as one patch release
(4.7.2), one commit per fix, each with a test, in this order. **None of these
sandboxes the checker**; the checker keeps running where it runs today.

### Fix 3 (first): timeouts and the stuck box
- `JudgeBase#run_bounded(cmd, timeout:)`: spawn in its own process group
  (`popen3` + `pgroup: true`), wait with a bounded join, KILL the group on
  expiry; returns `out, err, status, timed_out`.
- `Checker#process` uses it. Timed out → `CheckerResult.grader_error(comment:
  "(cafe-checker) checker timed out after N s")`, testcase `!`, submission
  continues. Default 30 s.
- `JudgeBase#run_initializer` uses it. Timed out → `GraderError` for the
  submission ("dataset initializer timed out") and the `worker_datasets` row
  is deleted so the next job retries. Default 120 s.
- Defaults in `worker.yml` under `limits: {checker_timeout: 30,
  initializer_timeout: 120}` (and `.SAMPLE`).
- `Grader.plan_box`: enabled box, process alive, heartbeat older than 600 s →
  `[:kill, pid]`; the next tick's existing path reclaims and respawns.
- Tests: `run_bounded` with `sleep`, a `plan_box` case in
  `test/engine/grader_watchdog_test.rb`, a sleeping-checker case in
  `test/engine/evaluator_checker_flow_test.rb`.

### Fix 2: retry guards
- `retry_error_job` and `retry_all_error_jobs` retry only jobs whose
  submission exists and whose chain is current (no newer compile job for the
  submission); rows superseded by a rejudge are skipped; the toast reports
  the skipped count. Clear All unchanged.
- Test in `test/controllers/graders_controller_test.rb`: one current, one
  superseded error job.

### Fix 1: rejudge and the unique index
- `Job.supersede!(submission)`: waiting and processing jobs of the submission
  → `error`, result "superseded by rejudge". Called first in
  `Submission#add_judge_job`.
- Chain check `Job.chain_current?(submission_id, chain_id)` (no compile job
  with a higher id for that submission): used after claim in
  `Grader#check_and_run_job`, before the evaluation write in
  `Evaluator#evaluate` (pass `chain_id:`), and before scoring. Needs an index
  on `jobs.arg`.
- Migration: delete orphan evaluation rows; dedupe remaining pairs keeping
  the newest id; replace `index_evaluations_on_submission_id` with a unique
  index on `(submission_id, testcase_id)`. **Time the build first** on a
  local copy (`CREATE TABLE zz_bench LIKE evaluations` + insert-select,
  7.3 M rows). `find_or_create_by` → `create_or_find_by`.
- Tests: model tests for supersede and the chain check; index assertion in
  the schema test.

Defaults taken, to confirm: the timeout values, Retry All current-chain-only,
chain check by job id rather than a generation column on `submissions`.

## 4. Sandboxing the checker: the full test it needs (phase 0, slice 0.3)

Not a hardening fix; it changes the grading path for every custom-checker
and PostgreSQL dataset and must be proven, not reasoned about.

1. Fix `ReplayDiff` first (slice 0.5 moves ahead of 0.3): compare points and
   per-testcase scores, one verdict vocabulary.
2. On the local prod copy, enumerate every dataset with `evaluation_type` in
   `custom_cafe`, `custom_testlib`, `custom_testlib_raw`, `cms_comparator`,
   `postgres`, `relative` (cp-grader: 35 + 4 + the relative ones).
3. For each, `Replay::ReplaySampler.sample(problem, limit: 100)` across score
   buckets; regrade through the sandboxed checker on a box no grader owns;
   `ReplayDiff` must report nothing beyond T→P / x→P. Record the table in the
   phase-0 ledger.
4. Fleet census of checker types across the eight web servers (the 2026-08
   census in `doc/decisions.md` shows how) so no host runs a type the sample
   did not cover.
5. `engine:smoke` on every judge host after deploy (already in the pipeline),
   plus one custom-checker submission per host chosen by hand.
6. Rollback: a `worker.yml` switch `checker_sandbox: false` for one release,
   so a host can fall back without a redeploy.

## 5. Spec revision 2: what to change

**Status 2026-10-08: done**, rev 2262. Everything below is in the spec,
plus §3's "where the code differs" notes (spec §8.1). Choices revision 2
made beyond this list, for review round 2 to check: the ceiling gets
allowances for compile, initializer and a cold-cache fetch (the bare
formula would cut off a 120 s initializer); "old blobs kept while jobs
reference them" is a fixed 24 h delayed purge plus `410 Gone` →
re-snapshot, not reference counting; a job fault's worker exclusion lapses
after 60 s so a pool of one still retries; the claim's filters run in SQL
(`jobs.requires`, `jobs.dataset_id`) so a quarantined dataset at the head
of the queue cannot starve it; a `grade` row starts a chain for the
legacy check; the agent runs as its own user `cafe-judge`.

Fold §2's decisions into the spec, section by section:

- §6.2/6.4/6.5: heartbeat lists `{job_id, lease}` pairs; `seq` unique per
  `(job, attempt)`; `complete(done)` rejected unless every snapshot testcase
  has a result; lease check + writes + transition in one transaction with
  the job row locked; 409 on a lost lease makes the agent kill the runner.
- §6.3: envelope stored on the job row; `job.generation` = job id;
  `submissions.current_job_id`.
- §6.6 + §9.9: three fault domains; quarantine for job/dataset faults;
  manual vs automatic pause.
- §7.1: `judge_workers.previous_token_digest`, `previous_valid_until`;
  `blob_digests` table; `evaluations` unique index; `jobs` index on
  `(status, job_type, priority DESC, id)` and the two-step claim.
- §7.2/7.4: dial change converts waiting `grade` jobs; shadow enqueue path
  separate from `add_judge_job`; score from the snapshot; 1-minute lease
  sweep; Retry All current-chain-only.
- §6.4 + §9.6: per-phase deadlines in the agent; server-side ceiling per job
  (`cost.estimate_s × 3 + 60 s`).
- §9.3: weighted service across servers; one scheduler owns the idle budget;
  `max_concurrency` counts jobs, `max_runners_per_job` caps spread; memory
  accounting; "compiles never queue behind small runs" → "a compile waits at
  most one small job".
- §9.5 + §10: PostgreSQL workspace namespaced by server + dataset hash
  (schema per workspace); checkers and initializers inside isolate; trust
  domain statement.
- §11: the s4 scenarios; cold-cache latency.
- New §: server-side state-transition table (generation, attempt, lease,
  shadow, rollback).
- §15: decision-log entries for the above and for dae's trust decision.

Then commit as "spec: judge worker pool, revision 2 after review round 1"
and ask for review round 2.

## 6. Decisions dae owes

1. **Trust boundary, interim — DECIDED 2026-10-04 (dae): accept the
   exposure** until phase 0 ships sandboxed checkers. No upload restriction
   meanwhile. The spec's decision log gets this entry in revision 2.
2. **Go for the three hardening fixes** with the defaults in §3, or change
   them — stated in the hardening thread's opening message.
3. **Thread order.** Hardening thread first (short, releasable), then the
   spec revision thread, then phase-0 planning.

## 7. How to resume

Hardening thread, first message:
> Read `doc/judge-worker-handoff-2026-10-04.md` §3 and §6. The §3 defaults
> stand unless I say otherwise here. Implement fix 3 as a bounded change,
> then fix 2, then fix 1; one commit each on master with a test; time the
> evaluations index build on a local copy before writing that migration;
> cut release 4.7.2 at the end with the `/release` skill.

Spec thread, first message:
> Read `doc/judge-worker-handoff-2026-10-04.md` §2, §5 and §6, then the spec
> at rev 2229. Write revision 2, including the server-side state-transition
> table and the trust decision in the decision log; commit it on master;
> then give me the review commands so I can send it for review round 2.

Both of the above are done (2026-10-08). The next two threads:

Review round 2, message for the **independent reviewing session** (paste the
diff it names, or let it read the file):
> Review revision 2 of `docs/superpowers/specs/2026-10-04-judge-worker-pool-design.md`
> (master rev 2262; `hg diff -r 2229 -r 2262` on that file shows what changed
> since revision 1). Round 1's points and how revision 2 answers them are in
> `doc/judge-worker-handoff-2026-10-04.md` §2 and §5; §5 also lists the
> choices revision 2 made beyond round 1 — check those first. Then check
> the spec against the grading-engine changes `master` made after revision
> 2, revs 2278–2286 (`hg log -r 2278:2286`; `hg diff -r 2262 -r 2286
> app/engine config/worker.yml.SAMPLE lib/tasks/engine.rake`): per-host
> isolate options and compiler options in `worker.yml` written by
> `engine:detect`, the `engine:langcheck` task, and a grader error for a
> language with no compiler on the host. They bear on §9.4 (languages),
> §9.6 (capabilities), §9.7 (config file) and slice 0.4 (`LanguageProfile`).
> Report only defects that would change the envelope, the result-sink
> interface, the state table (§7.8) or the phase-0 slice list, since those
> are what the phase-0 plan is built from.

Round-2 verification thread (this repo, new session), first message:
> Read `doc/judge-worker-handoff-2026-10-04.md` §1, §2 and §5, then the spec
> at rev 2262. Here is review round 2: [paste]. Verify every point against
> the code and the local prod copy as round 1 was verified, tell me which are
> real, fold the real ones into the spec as revision 3 together with what
> revs 2278–2286 change for the agent, commit on master, and append the
> round-2 table to this handoff §2.

Phase-0 planning thread, first message (only after the spec is approved):
> Read `doc/judge-worker-handoff-2026-10-04.md`, then the approved spec. Use
> the writing-plans skill to write the phase-0 plan only (engine extraction,
> slices 0.1–0.5 plus the sandboxed checker from §4 as its own slice with
> the full test), with a ledger, under `docs/superpowers/plans/`.

Useful commands:

```
hg log -r 2229 --stat
glow -w 0 docs/superpowers/specs/2026-10-04-judge-worker-pool-design.md
hg log -r 'desc("Co-Authored-By")' -l 3 --template '{rev} {date|shortdate} {desc|firstline}\n'
```
