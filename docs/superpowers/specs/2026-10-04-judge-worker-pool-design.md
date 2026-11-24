# Judge Worker Pool — Design

**Date:** 2026-10-04 (revision 1), 2026-10-08 (revision 2)
**Status:** Revision 2, written after review round 1; pending review round 2.
Approach approved in discussion (dae, 2026-10-03/04).
**Revisions:** revision 1 = rev 2229. Revision 2 adds what review round 1
decided (`doc/judge-worker-handoff-2026-10-04.md` §2), the server-side
state-transition table (§7.8), the fault domains (§6.7), the interim trust
decision (§10, §15), and what the hardening fixes in release 4.7.2 (revs
2251–2254) changed in the legacy path (§8.1). Every section revision 2
changed says so in the decision log (§15).
**Scope:** replaces the per-server judge worker (`Grader.start`, one Rails
process per isolate box, polling the server's own MySQL) with a pool of
database-less workers that serve any server over a versioned HTTP protocol.
**Related:** `doc/backlog.md` "Language-specific options in the database
(issue #42)" (its *Reopen when* condition is this design); migration
`20260908120000_add_status_priority_id_index_to_jobs.rb` (the 2024–25
"more boxes = slower polling" root cause); `app/engine/replay/*` and
`app/engine/engine_smoke.rb` (the equivalence harness this design reuses);
`doc/judge-worker-handoff-2026-10-04.md` (review round 1 outcomes, the
hardening fixes, the checker-sandbox test plan).

## 1. Problem

Every cafe-grader deployment ("server") needs its own judge host, and that
judge host can serve only that server. The worker is not a client of the
server; it *is* the server's code: `Grader.start` is `rails runner` from the
same checkout on the same `database.yml`, it polls the `jobs` table directly,
calls `Submission.find` / `Dataset.find` / `Testcase.find`, writes `Evaluation`
rows and heartbeats into `grader_processes`. Only files cross HTTP
(`WorkerController`, one shared passcode). Consequences:

- Eleven servers need eleven sets of boxes; idle capacity on one cannot help
  a burst on another.
- The worker assumes the server's schema. The fleet runs two branches
  (`master` on compas / cg / toi / template, `chula_cp` elsewhere), so one
  pooled checkout of today's worker cannot serve all of them.
- Every id the worker holds is bare (`jobs.arg` = submission id, cache dir
  `problem_id/dsid_N/testcase_id`, `worker_datasets(worker_id, dataset_id)`),
  so nothing says which server an id belongs to.
- Each box costs a full Rails process (365–631 MB resident on cp-worker), one
  MySQL connection, ~20 queries per testcase, five polls per second when idle,
  and one HTTP download of the compiled binary **per testcase** (3 MB average,
  23 MB max; ~14 testcases per compile), which is ~40 % of all Apache requests
  on cp-grader.

**Goal:** one worker program that serves any number of servers, with no
database access, no schema coupling, no per-testcase binary transfer, fewer
server round trips, and better failure diagnostics than today's error card.

**Non-goals (this spec):** a central broker (approach C, §14), a cross-server
fleet dashboard, moving language settings into the `languages` table
(groundwork only, §9.4), changing how students or problem setters use the
site.

## 2. Terms

One name per thing; these names are used throughout the code, the API and
the admin pages.

| Term | Meaning |
|---|---|
| **server** | one cafe-grader deployment: Rails app + its own MySQL. Owns submissions, datasets, the queue and the grade. |
| **worker** | one judge host. Runs one **agent**. Serves one or more servers. Has a name (e.g. `cp-worker-1`). |
| **agent** | the worker's supervisor process. Talks to servers, owns the runners, the cache and the logs. |
| **runner** | one child process of the agent bound to one isolate **box** for its whole life. Executes one job phase at a time. |
| **box** | one isolate sandbox (`isolate -b N`). Box ids are per host. |
| **lane** | a group of runners reserved for one phase: the **compile lane** and the **run lane**. |
| **job** | one unit of work on the wire. Day one has one **kind**: `grade` = compile + run every testcase of one submission against one dataset. Each job has a server-side id and a **lease**. |
| **generation** | one grading of one submission, named by the id of the job that started it: the `grade` job's id on the pool path, the compile job's id on the legacy path (where the shipped code calls it the *chain id*, `Job#chain_id`). A rejudge starts a new generation; `submissions.current_job_id` holds the current one. Only the current generation may write the submission's grade. |
| **envelope** | the self-contained JSON description of a job: everything the engine reads today, plus file URLs with content hashes. Built once when the job is enqueued and stored on the job row. |
| **snapshot** | the `dataset` part of a stored envelope: testcase ids, weights, groups, limits, score type and file hashes as they were at enqueue. A generation is run and scored against its snapshot, never against the live dataset. |
| **claim** | the request by which an agent takes jobs from a server and receives envelopes with leases. |
| **attempt** | one claim of a job. Each claim increments `jobs.attempts` and issues a new lease token; events are numbered per attempt. A job that goes back to the queue keeps its generation and its envelope and gets a new attempt. |
| **lease** | the time-bounded ownership of a job by one worker for one attempt, identified by a lease token. Renewed by progress and heartbeat; expired leases are swept back to the queue. |
| **ceiling** | the longest one attempt may hold a job however often its lease is renewed, counted from the claim: `cost.estimate_s × 3 + 60 s`, plus the worst case of the phases before the run — the compile timeout, the initializer timeout when the dataset has an initializer, and 1 s per MB of the snapshot's files (a cold cache). The server computes it from the envelope. Stops a hung runner that the agent keeps renewing. |
| **capability** | something a worker can do, detected at start and reported in every heartbeat (`lang:cpp`, `postgres`, `cg`, `net`, `mem:8192`). An envelope lists what it **requires**. |
| **cost** | the server's estimate of a job's sandbox time: testcases × time limit. Drives the compile lane's prefetch, the small-job reserve and the ceiling. |
| **dial** | `GraderConfiguration['judge.pool_share']`, the percentage of new submissions enqueued as `grade` jobs instead of the legacy compile/evaluate/score chain. |
| **shadow** | a `grade` job flagged `shadow: true`, enqueued by its own path beside a legacy generation: graded by the pool, result stored in `shadow_gradings` and diffed, never written to the submission or its evaluations, never shown to students. |
| **verdict** | a grading outcome caused by the submission: compile error, wrong answer, crash, timeout, partial. Never an error. |
| **infrastructure error** | a failure caused by something other than the submission. Each one belongs to one **fault domain** (§6.7), which decides what stops: the job, the dataset, the worker, or the agent's traffic to one server. |
| **quarantine** | a dataset held out of the pool after a dataset fault (§6.7): its waiting jobs stay waiting, unclaimed, until staff fix the dataset and release it. Jobs keep their attempts. |
| **legacy path** | today's in-process boxes and their compile / evaluate / score jobs. Kept until phase 4. |

## 3. Measured facts the design rests on

Collected 2026-10-03 by read-only ssh and from the local prod copy of
cp-grader's DB.

| Fact | Value |
|---|---|
| cp-worker 10.0.5.81 | 32 cores, 32 GB, no swap; 8 boxes; every sandbox run in 24 h had CPU/wall ≥ 0.95 (no core contention) |
| cp-grader 10.0.5.50 | 8 cores, 16 GB; Passenger max pool 6; MySQL defaults |
| Worker share of cp-grader's Apache requests | ~40 % (6,095 of 15,611 one day; 9,955 of 23,397 the next), ~93 % of it `get_compiled_submission` |
| Compiled binary | 3 MB average, 23 MB max; ~14 testcases per compile → ~40 MB per submission through Passenger |
| Testcase corpus on cp-grader | 14,266 files, 663 KB average, 9.0 GB total |
| Peak load, last 12 months | 77 submissions/min; 528 per 10 min (2026-04-09 08:20 Bangkok); 5,239/day |
| 16-box experiment | boxes 9–16 on cp-worker 2024-11-03 → 2025-06-13; symptom: poll interval stretched with box count; cause: no index on `jobs.status` until 2026-09-08 (full scan per poll; every `FOR UPDATE SKIP LOCKED` claim locked every row it scanned; 353 of 1,200 concurrent claims came back empty) |
| Worker logs | `log/judge.log` on cp-worker is 121 GB, unrotated |
| Code outside the student sandbox (verified 2026-10-04) | custom checkers (`Checker#process`) and dataset initializers (`JudgeBase#run_initializer`) run on the judge host as the app user, not in isolate. cp-grader has 35 custom-checker datasets and 4 PostgreSQL datasets; 18 admins and 39 enabled group editors can upload a checker |
| Duplicate evaluations (verified 2026-10-04) | the 312 duplicate `(submission, testcase)` pairs all belonged to deleted submissions (4,279 orphan rows, `submission_id` NULL); none came from a rejudge race. Removed by the 4.7.2 migration, which then built the unique index: 30 s end to end on the prod copy's 7.56 M rows, 11 s of it the online index build |
| Scheduled tasks (found 2026-10-08) | from the 2026-09-17 deploy until 4.7.3 no Solid Queue worker served the recurring-task queue, so on all nine web hosts the job reclaim (`grader_job_reclaim`) and the nightly cleanup (`Grader.cleanup_web` → `Job.clean_old_job`) never ran; the prod copy of 2026-10-07 held 249k successful job rows back to 2026-09-16 (`doc/decisions.md` 2026-10-08). A design that relies on a recurring task must make its silence visible (§7.5) |

## 4. Decision

**Approach B, the protocol worker.** The worker is a thin client that never
touches a database. Each server exposes a versioned judge API. The unit of
exchange is the envelope.

Rejected, **approach A** (pooled Rails worker with per-origin
`connected_to`): needs every worker to hold every server's DB credentials and
network reach, loads one set of models against drifting schemas, and wraps
ActiveRecord calls scattered across compiler / evaluator / checker / scorer,
so it pays a rewrite without buying decoupling.

Deferred, **approach C** (central broker): B plus one always-on service. Buys
worker discovery and cross-server priority; costs one more thing to run. B is
designed so C is a drop-in: the envelope, lease and report protocol are
identical, only the claim step changes from polling servers to reading a
broker. Reconsider when the server × worker matrix becomes painful (§14).

Settled sub-decisions (dae, 2026-10-03/04), each with its reason in the
section that implements it: wire unit = one submission (§6.3); scoring moves
server-side (§7.4); lanes replace the per-box job-type filter (§9.3); one
bearer token per worker × server pair (§10); failure reports and the event
timeline are first-class protocol objects (§6.6, §7.5); everything lands on
`master` in releasable slices, no feature bookmark (§12); until checkers
are sandboxed, the exposure of unsandboxed checkers is accepted and no
upload is restricted (§10).

## 5. Architecture

```
 server A (Rails + MySQL)            server B                 server C (no judge API yet)
   jobs table = queue                  jobs table                  jobs table
   judge API v1  ◄──────┐              judge API v1 ◄──┐           legacy boxes only
   Graders page         │                              │
                        │ HTTPS, bearer token          │
                 ┌──────┴──────────────────────────────┴──────┐
                 │ agent  (cp-worker-1)                        │
                 │  claim loop per server · heartbeat · policy │
                 │  local scheduler · cache (by sha256)        │
                 │  runners: compile lane [1 2] run lane [3..8]│
                 └─────────────────────────────────────────────┘
```

- The server keeps the `jobs` table as its queue and adds the claim endpoint
  beside today's `take_oldest_waiting_job`, with its own two-step claim
  (§6.2). No new component.
- The agent polls each server it is configured for, in its own thread, only
  while it has an idle runner, and asks for up to *k* jobs at once.
- Files travel server → worker once per content hash. Results travel
  worker → server as small JSON. The compiled binary never leaves the worker.
- The server owns every DB write: evaluation rows, submission status, the
  score, the timeline.

## 6. Protocol: judge API v1

All endpoints live under `/judge/v1/` on each server, JSON in and out,
`Authorization: Bearer <token>`. Documented as an rswag spec so
`swagger/judge/v1.yaml` is the contract both sides test against (§11).

### 6.1 Versioning

Every request carries `X-Judge-Protocol: 1` and `X-Judge-Agent: <version>`.
A server answers `426 Upgrade Required` with its supported range when the
protocol is outside it; the agent logs once and stops polling that server
until the next config reload. Within a major version, fields are only added,
never removed or re-typed. A worker serves any server whose range includes
its version, so the fleet never needs lock-step deploys.

### 6.2 Endpoints

| Method, path | Purpose | Notes |
|---|---|---|
| `POST /judge/v1/heartbeat` | register / keep alive; report capabilities, runner counts, disk, version, automatic pause (§6.7), and the jobs it holds as `{job_id, lease}` pairs; receive **policy** (§7.6) | every 5 s; renews only the pairs whose lease token is the job's current one; the reply lists the other pairs as `lost`; the reply is the server's per-worker policy, so a pause on the page reaches the agent within one beat |
| `POST /judge/v1/claim` | take up to `max` jobs this worker can run | body: `{max, capabilities, lanes:{compile_idle, run_idle}}`; reply: `{jobs:[envelope…], retry_after_ms}`; **two-step claim**, below |
| `GET /judge/v1/files/:sha256` | fetch a file by content hash | `Content-Length` and the hash are verified by the agent; a mismatch is an infrastructure error; a hash the server no longer holds is `410 Gone` (§6.7) |
| `POST /judge/v1/jobs/:id/progress` | one or more events for a leased job; extends the lease | body: `{lease, events:[…]}`; idempotent per event: `seq` is unique per `(job, attempt)` |
| `POST /judge/v1/jobs/:id/complete` | final result or failure; releases the lease | idempotent: a repeat with the same lease is a 200 no-op; `done` is refused (422, listing the missing testcase ids) unless every snapshot testcase has a result |
| `POST /judge/v1/jobs/:id/release` | give the job back unprocessed (drain, policy change) | job returns to `wait`; a release does not use up an attempt |

**Rules every job request obeys** (progress, complete, release; review
round 1 point 3):

1. **One transaction, job row locked.** The server locks the job row
   (`SELECT … FOR UPDATE` by primary key), checks the lease, writes the
   events or the result, and moves the job's state, all in one transaction.
   A request either lands whole or not at all.
2. **The lease check** passes only when the job is in `process`, the worker
   is the one that claimed it, the lease token is the job's current one
   (so it belongs to the current attempt), the ceiling has not passed, and,
   for a non-shadow job, the job is the submission's current generation
   (`submissions.current_job_id = job.id`).
3. **A failed lease check is `409 lost`**, nothing is written, and the event
   is logged. The agent stops the runner working on that job (kills its
   process group), drops the job and its local results, and does not retry.
   A heartbeat's `lost` list has the same effect. One exception keeps
   `complete` idempotent: a `complete` carrying the lease token of the
   attempt that already completed the job, with the same outcome, is
   `200` and changes nothing (the finished job keeps that token).
4. **`seq` is unique per `(job, attempt)`**, enforced by a unique index on
   `judge_job_events`; a repeated `seq` is skipped, so a retried request
   never writes twice. A new attempt starts again at `seq` 1.
5. **Evaluation writes are upserts on `(submission_id, testcase_id)`**, the
   unique index shipped in 4.7.2 (rev 2253), and only for testcase ids in
   the job's snapshot (another id is 422).

**Two-step claim** (review round 1 point s2). Today's
`take_oldest_waiting_job` locks the oldest waiting row inside one locking
read. A claim that also filters by capabilities, quarantine and excluded
workers would scan rows those conditions skip, and InnoDB keeps the lock on
every row a locking read scans — the 2024 slow-polling bug again (§3). So:

1. *Candidates, no locks:* a plain `SELECT id` (not a locking read, so it
   may scan as many rows as it needs) over the index `(status, job_type,
   priority DESC, id)` for waiting `grade` jobs, with every filter in SQL:
   `JSON_CONTAINS(:capabilities, jobs.requires)` (the job's `requires` ⊆
   the worker's capabilities), `jobs.dataset_id` not quarantined, and this
   worker not in `excluded_worker_ids` unless the job has waited 60 s
   (§7.8 T3); `LIMIT 2 × max`. The filters must be in SQL: filtering in
   Ruby after the `LIMIT` would return nothing whenever the oldest jobs all
   belong to a quarantined dataset or need a capability this worker lacks,
   even with claimable jobs behind them. `max` is already cut to what the
   server's policy for this worker allows (§7.6).
2. *Lock one by primary key:* for each candidate in order, `SELECT … FOR
   UPDATE SKIP LOCKED WHERE id = ? AND status = wait`; a row that is gone or
   locked is skipped. Claim it (§7.8 transition T3), commit, and stop at
   `max`.

The legacy `WorkerController` endpoints and the shared passcode stay for the
legacy path until phase 4.

### 6.3 Envelope

One job = one submission against one dataset. Inside the worker the compile
and run phases are separate, and testcases of one submission may spread
across idle run-lane runners, so today's per-testcase parallelism is kept
without the protocol knowing. The compiled binary stays on the worker's disk.

```json
{
  "protocol": 1,
  "job": {
    "id": 123456, "kind": "grade", "shadow": false, "priority": 0,
    "attempt": 1,
    "lease": {"token": "…", "expires_at": "2026-10-04T09:00:00Z"},
    "cost": {"testcases": 14, "time_limit": 1.0, "estimate_s": 14.0},
    "requires": ["lang:cpp"]
  },
  "server": {"name": "cp-grader", "base_url": "https://grader.nattee.net/grader"},
  "submission": {
    "id": 987654, "language": "cpp",
    "source": {"inline": "…", "filename": "main.cpp"}
  },
  "language": {
    "name": "cpp", "exec_filename": "a.out", "need_cg": false,
    "isolate_options": "", "compile_timeout_s": 10
  },
  "dataset": {
    "id": 5566, "problem_id": 712, "problem_name": "d05_queue",
    "time_limit": 1.0, "memory_limit": 256,
    "evaluation_type": "default", "score_type": "sum",
    "main_filename": null, "initializer_filename": null,
    "files": {
      "checker": {"name": "checker", "sha256": "…", "bytes": 48213, "mode": "0755"},
      "managers": [], "initializers": [], "data_files": []
    },
    "testcases": [
      {"id": 9001, "num": 1, "code_name": "1", "group": 1, "weight": 10,
       "input":  {"sha256": "…", "bytes": 1024},
       "answer": {"sha256": "…", "bytes": 12}}
    ]
  }
}
```

- `requires` is derived by the server: the language, plus `postgres`,
  `net`, `cg` when the dataset or language needs them. The claim only returns
  jobs whose `requires` ⊆ the worker's capabilities.
- `source.inline` is used up to 256 KB, otherwise `source.sha256` and the
  file endpoint. Submission sources are text in the DB today, so inline is
  the normal case.
- `language` carries what the engine reads per language today
  (`Problem#exec_filename`, `JudgeBase#isolate_options_by_lang`,
  `#isolate_need_cg_by_lang`, the compiler's timeout). The agent's engine
  has the per-language compile classes keyed by `language.name`; values in
  the envelope override the engine's constants. This is the hook for
  languages-as-data (§9.4).
- Every file is referenced by `sha256`; the agent fetches only hashes it does
  not already hold.
- Settings (limits, evaluation type, score type) are never cached on the
  worker; they arrive with every job. This removes today's
  `WorkerDataset.delete_all` invalidation entirely.
- **The envelope is built once, at enqueue, and stored on the job row**
  (`jobs.envelope`). A claim adds only the `attempt` and `lease` fields.
  Every attempt of a generation therefore runs the same snapshot, and the
  server scores that snapshot (§7.4). A dataset edited while a job waits
  does not change the job; staff rejudge after editing, as today. The one
  exception is a change to the set of testcases, caught at complete (§7.8
  T7).
- `job.id` is the generation; there is no separate generation column on
  `jobs`. `submissions.current_job_id` points at the current generation
  (§7.1).

### 6.4 Lease

- `claim` sets `jobs.status = process`, `judge_worker_id`, a new
  `lease_token`, `lease_expires_at = now + 120 s`, `deadline_at = now +
  ceiling`, and increments `attempts`.
- Every `progress` that passes the lease check, and every `heartbeat` pair
  `{job_id, lease}` whose token is the job's current one, extends the lease
  by 120 s. The heartbeat never renews by job id alone: a pair from an
  older attempt is answered as `lost`.
- **The lease sweep**, a new Solid Queue recurring task `judge_lease_sweep`
  that runs **every minute**, handles two cases (§7.8 T12–T14):
  - *lease expired* (`lease_expires_at` passed): the job goes back to `wait`
    as the same generation, with the same envelope, if the dial still
    routes its submission to the pool; if the dial no longer does, the
    sweep converts it to a legacy generation through
    `Submission#add_judge_job`. Three attempts used → `error`, and the
    submission → `grader_error` as today.
  - *ceiling passed* (`deadline_at` passed, however recently renewed): the
    same, counted as a job fault of class `timeout`; the job id goes into
    that worker's next heartbeat reply as `lost`, so the agent kills the
    runner.
- The 1-minute sweep replaces the 10-minute `grader_job_reclaim` interval
  (30 minutes stale) for `grade` jobs; `grader_job_reclaim` keeps serving
  the legacy path. Its last run is shown on the Graders page (§7.5),
  because a recurring task can stop without a sound (§3).
- The `ps`-based watchdog has no equivalent for remote workers; the lease
  and the ceiling replace it. Inside the worker, every phase has its own
  deadline (§9.6), so the ceiling is the server's backstop, not the first
  line.

### 6.5 Progress events

| `type` | Payload | Server effect |
|---|---|---|
| `claimed` | lane, runner | timeline only |
| `compiled` | `ok`, `compiler_message` (≤ 15,000 chars), `elapsed_ms` | `submissions.status` → `compilation_success` / `compilation_error` + `compiler_message`, exactly today's fields; on failure the agent then sends `complete(compilation_error)` |
| `testcase` | `testcase_id`, `result`, `time_ms`, `memory_kb`, `score`, `result_text` (≤ 250), `isolate_message`, `cpu_ms`, `wall_ms` | `Evaluation` upsert on `(submission_id, testcase_id)` (`find_by || create_or_find_by!`, as the legacy evaluator writes since 4.7.2); for a shadow job, a row in `shadow_gradings.evaluations` instead |
| `note` | free text ≤ 1 KB | timeline only (e.g. "cache miss, fetched 14 files, 9.2 MB") |

Events carry a `seq` that is unique per `(job, attempt)` (§6.2 rule 4).
Events may be batched; the agent flushes at most every 500 ms or 20 events.
A shadow job's events never touch the submission or its evaluations.

### 6.6 Complete and failure report

```json
{"lease": "…", "outcome": "done",
 "max_runtime_ms": 812, "peak_memory_kb": 10240}
```

`outcome` ∈ `done` (all testcases reported), `compilation_error`,
`infrastructure_error`. Giving a job back unprocessed is the separate
`release` endpoint (§6.2), never a `complete`. On `done` the server first
checks that every snapshot testcase has an evaluation row, and refuses with
422 and the missing ids if not; then it scores (§7.4). On
`infrastructure_error` the body carries the **failure report**:

```json
{"lease": "…", "outcome": "infrastructure_error",
 "failure": {
   "class": "missing_compiler | disk_full | isolate_failed | fetch_failed |
             file_gone | hash_mismatch | bad_envelope | initializer_failed |
             agent_exception | timeout",
   "phase": "fetch | init | compile | run | check",
   "testcase_id": 9003,
   "message": "…", "exception": "Errno::ENOSPC: …",
   "isolate_meta": {"status": "XX", "message": "…"},
   "agent_log_tail": "… last 8 KB of this job's log …",
   "job_dir": "/var/lib/cafe-judge/jobs/cp-grader/123456"
 }}
```

Server effect: decided by the class's fault domain (§6.7) and listed
transition by transition in §7.8. The failure report is stored on the
job's timeline either way and shown on the Graders page.

A checker that crashes or times out on one testcase is **not** an
infrastructure error: the testcase gets `!` and the submission continues,
as the legacy path does since 4.7.2 (rev 2251).

### 6.7 Fault domains

Revision 1 paused a worker for every infrastructure error, so one bad
dataset would pause every worker in turn as each claimed one of its jobs
(review round 1 point 6). Revision 2 sorts every failure into the one
domain it belongs to; each domain stops only what is broken.

| Domain | Classes | What stops | How it ends |
|---|---|---|---|
| **job** — this submission × dataset fails, others are fine | `agent_exception` (a runner crash counts as one) or `isolate_failed` on one job, `timeout` (ceiling passed), a 422 on complete | the job: back to `wait` with this worker in `excluded_worker_ids` (another worker gets it first; this one may take it again after 60 s, so a pool of one still retries); after its third attempt, `error` and the submission `grader_error`, as today | staff Retry or rejudge (§8.1) |
| **dataset** — every job of this dataset would fail | `initializer_failed`, `file_gone` (410: the server no longer holds a file of the snapshot), `hash_mismatch` after three fetches, `bad_envelope`; or three job faults of one class from three different jobs of one dataset within 10 minutes | the dataset is **quarantined** for the pool: claims skip its jobs, which stay waiting with their attempts unspent | staff fix the dataset and press *Release* on the Graders page; a `file_gone` job is first re-snapshotted as a new generation (§7.8 T11) |
| **worker** — this host is broken for every server | `missing_compiler`, `disk_full`; `isolate_failed` twice or `agent_exception` three times within 10 minutes, on any jobs | the agent **pauses itself for every server** (automatic pause), and the job goes back to `wait` without spending an attempt | automatic: the agent's own check (`cafe-judge check`, every minute while paused) passes again |
| **server or network** — one server is unreachable or failing | connection refused, timeouts, 5xx, 429, `fetch_failed` after three tries | the agent **backs off from that server** (1 s doubling to 60 s) and keeps serving the others; running jobs finish and post their results when the server answers, or their leases expire and the sweep takes over | automatic: the next request succeeds |

**Manual pause is a separate flag.** An admin's pause (`judge_workers.paused`,
per server, audited) is never cleared automatically; an automatic pause
(`auto_paused_at`, `auto_pause_reason`, reported in the heartbeat) is never
cleared by an admin's *Resume*. The page shows both, so "paused" always
says who paused it and why.

## 7. Server side

### 7.1 Data model

- `jobs`: new columns `judge_worker_id` (nullable), `lease_token`,
  `lease_expires_at`, `deadline_at`, `attempts` (default 0), `shadow`
  (boolean), `envelope` (JSON, the stored envelope, §6.3), `requires`
  (JSON array, copied from the envelope) and `dataset_id`, so the claim can
  filter in SQL (§6.2), `excluded_worker_ids` (JSON array), and the new
  `job_type` value `grade: 4` (`preprocess` stays unused). Indexes: `(status, job_type,
  priority DESC, id)` for the two-step claim (§6.2); `(status,
  lease_expires_at)` and `(status, deadline_at)` for the sweep.
  `(status, priority DESC, id)` (2026-09-08) stays for the legacy claim and
  `arg` (4.7.2, rev 2253) for the chain check.
- `submissions`: new column `current_job_id` (nullable), the current
  generation. `Submission#add_judge_job` sets it on both paths: to the
  `grade` job's id or to the legacy compile job's id.
- `datasets`: new columns `judge_quarantined_at`, `judge_quarantine_reason`
  (§6.7). Setting and releasing them is audited.
- `evaluations`: the unique index on `(submission_id, testcase_id)` already
  exists (4.7.2, rev 2253, after deleting 4,279 orphan rows).
- `judge_workers`: `name` (unique), `token_digest`, `previous_token_digest`,
  `previous_valid_until`, `protocol_version`, `agent_version`,
  `capabilities` (json), `runners_total`, `runners_busy`, `disk_free_mb`,
  `last_heartbeat`, `paused` (boolean, manual), `pause_reason`,
  `auto_paused_at`, `auto_pause_reason`, `max_concurrency` (nullable, in
  jobs), `max_runners_per_job` (nullable), `allowed_kinds` (string, default
  all), `last_failure` (json), `created_by_id`, `revoked_at`. **Audited**
  via `Auditable` (`audited only: %i[name paused max_concurrency
  max_runners_per_job allowed_kinds revoked_at]`; the digests are never
  logged — token changes are the manual actions of §7.7).
- `judge_job_events`: `job_id`, `attempt`, `judge_worker_id`, `seq`, `type`,
  `at`, `payload` (json); unique index `(job_id, attempt, seq)`. Trimmed
  with the job by `Job.clean_old_job`.
- `shadow_gradings`: `submission_id`, `job_id` (the shadow job),
  `live_job_id` (the legacy generation it shadows), `judge_worker_id`,
  `points`, `grader_comment`, `evaluations` (json per testcase), `status`
  (`pending | graded | failed | superseded`), `diff_verdict` (`same |
  benign | mismatch | structural`, from `Replay::ReplayDiff`), `created_at`.
  Kept 90 days.
- `blob_digests`: `blob_id` (unique), `sha256` (indexed), `byte_size`.
  Active Storage records only an MD5 checksum, so the SHA-256 the protocol
  names files by is computed when a dataset or testcase file is attached
  (filled for existing blobs by a one-off task). The files endpoint looks
  the hash up here.
- **File retention.** Today replacing a checker purges the old blob at once
  (`DatasetsController`), so a job waiting with the old snapshot would ask
  for a file that is gone. Every file a snapshot can name (checker,
  managers, initializers, data files, testcase input and answer) is
  instead detached at once and purged **24 hours later**, the longest a job
  can stay in the queue (`Job::MAX_RECLAIM_AGE`). A request for a purged
  hash is `410 Gone`, which §6.7 handles as a dataset fault that
  re-snapshots the job.

### 7.2 Routing: the dial

`Submission#add_judge_job(dataset, priority)` consults:

| Key | Type | Meaning |
|---|---|---|
| `judge.pool_share` | integer 0–100 | percentage of submissions enqueued as `grade`; selection is `submission.id % 100 < share`, so it is deterministic and reproducible |
| `judge.pool_languages` | string, optional | comma list; when set, only these languages are eligible for the pool |
| `judge.pool_problems` | string, optional | comma list of problem ids; same |
| `judge.shadow_share` | integer 0–100 | percentage of submissions that **also** get a `shadow` grade job; applies to submissions routed to the legacy path |

A rejudge or dataset re-grade goes through the same method and the same
dial.

**A dial change converts the waiting jobs it strands** (review round 1
point 4). Revision 1 relied on the sweep alone, which touches only leased
jobs, so a waiting `grade` job would wait forever once the dial went to 0
and no worker was left. Now saving any of the four keys runs
`JudgeRouting.reconcile!` after commit: every waiting, non-shadow `grade`
job whose submission the dial no longer routes to the pool is converted
through `Submission#add_judge_job`, which supersedes it and starts a legacy
generation (§7.8 T15). Leased jobs finish on their worker; if a lease
expires instead, the sweep converts the job the same way (T13). Waiting
legacy chains are never converted to the pool: the legacy boxes serve them
until phase 4. Setting the share to 0 is therefore the whole rollback.

**The shadow path is separate.** A shadow job is enqueued by
`ShadowGrading.enqueue(submission, live_job_id)`, called by `add_judge_job`
after it has created the legacy chain. It builds its own envelope from the
same dataset, creates a `shadow_gradings` row (`pending`), and never calls
`add_judge_job` itself, so it never supersedes the live generation or
deletes its evaluations (review round 1 point 1). Its retries go back to
`wait` like any job (§7.8 T12) but never touch the submission; after three
attempts the shadow row is `failed` with the failure report. The diff runs
when both the shadow job and the live generation are final, triggered by
whichever finishes second. A rejudge supersedes the shadow job together
with the live generation, and its row becomes `superseded`, not diffed.

### 7.3 Legacy path exclusion

`Job.take_oldest_waiting_job(grader_process, …)` restricts the legacy caller
to `%w[compile evaluate score]` regardless of the box's `job_type` filter.
Today a blank filter means *every* kind; without this change the old boxes
would claim `grade` jobs and fail them with "no handler".

The legacy chain check must also see pool generations. `Job#chain_id` and
`Job.chain_id_expression` (4.7.2) treat only a compile row as the start of
a chain; a `grade` row has no `parent_job_id`, so its id would be left out
of the newest-chain maximum, and a legacy chain overtaken by a rejudge onto
the pool would still look current. Slice 1.2 makes a `grade` row start a
chain the way a compile row does (its own id), so the legacy check and the
pool check (`current_job_id`) always agree on which generation is current.

### 7.4 Scoring on complete

`complete(outcome: done)` runs `Scorer` server-side over the `Evaluation`
rows and calls `Submission#set_grading_complete`, exactly what the legacy
score job does on a box. No queue wait for the score. The legacy path keeps
its score job until phase 4.

**Score from the snapshot.** Today `Scorer#process` compares the
submission's evaluations with the *live* dataset's testcase ids and fails
with "Evaluations are missing, please rejudge" when they differ (review
round 1 point 2). For a `grade` job the scorer reads the snapshot instead:
its testcase ids, weights, groups and score type. It runs inside the
complete transaction, after the lease check, so only the current
generation writes a score. One case cannot be scored safely: the live
dataset's set of testcases no longer equals the snapshot's (a testcase was
added or deleted while the job ran), so the evaluation rows would point at
testcases that are gone or leave new ones blank. Then the server starts a
new generation instead of scoring (§7.8 T7), which repairs what the legacy
path reports as an error.

### 7.5 Diagnostics on the Graders page

The page keeps its queue card and the errored-job list with Retry All /
Clear All, and gains:

- **Judge Workers card**: one row per `judge_workers` row — name, versions,
  capabilities, runners busy / total on this server, disk, last heartbeat,
  current jobs, last failure, the manual pause and the automatic pause
  shown apart (§6.7), and the controls: pause / resume, max concurrency,
  max runners per job, allowed kinds, token rotate / revoke.
- **Health line** above the card, turning red when something that should be
  running is not: the lease sweep's last run is older than 5 minutes (§6.4);
  `grade` jobs are waiting and no worker has sent a heartbeat for a minute;
  a dataset is quarantined.
- **Quarantined datasets**: one row per dataset with its reason and the
  failure reports that caused it, a link to the dataset, and *Release*.
- **Job timeline**: each job links to its events, in order, with worker,
  lane, per-testcase CPU vs wall time, and the failure report when present.
  Infrastructure errors show the class, phase, exception and the agent log
  tail inline, and offer the envelope as a download for `cafe-judge replay`.
- **Shadow card**: counts per `diff_verdict` for the last 7 days and the
  mismatches, each linking to the submission and the shadow result.
- **Legacy boxes card**: today's per-box list, unchanged, until phase 4.

Verdicts (compile error, wrong answer, crash, timeout) never appear on the
error card; only infrastructure errors do.

### 7.6 Policy in the heartbeat reply

```json
{"paused": false, "pause_reason": null, "max_concurrency": 4,
 "max_runners_per_job": 4, "allowed_kinds": ["grade"],
 "lease_seconds": 120, "poll_ms": 200, "lost": [123450]}
```

The agent applies it immediately: a pause stops claims from that server
(running jobs finish); a lower `max_concurrency` (counted in jobs, in any
lane) stops claims until that server's jobs drop below it;
`max_runners_per_job` caps how many run-lane runners one submission's
testcases may spread over (§9.3); `poll_ms` lets a server slow idle polling
fleet-wide; every job id in `lost` is stopped and dropped (§6.2 rule 3).

### 7.7 Token page

Under the Judge Workers card: *New worker* asks for a name, shows the token
**once**, stores a `BCrypt` digest. Rows are created only here; a heartbeat
with an unknown or revoked token is 401 and creates nothing. *Rotate*
issues a new token: the old digest moves to `previous_token_digest` with
`previous_valid_until = now + 10 minutes`, so an agent keeps working until
its config is reloaded with the new token; a request is accepted when its
token matches either digest that is still valid. *Revoke* sets
`revoked_at` and clears both digests; the next request gets 401. Each is
one manual audit row — actions `create_worker`, `rotate_token`,
`revoke_token` — with a badge in `AuditLogsHelper#audit_action_badge`.

### 7.8 State transitions (server side)

Every way a pool job's row can change, in one table (review round 1 asked
for this before phase 0). Agent-side states wait for the phase 2 plan.

**Job states:** `wait`, `process` (leased to one worker for one attempt),
`success`, `error`. Two facts sit beside the state: whether the job is the
submission's current generation (`submissions.current_job_id = jobs.id`),
and whether its dataset is quarantined. *Clear the attempt* below means: in
the same transaction, delete the submission's evaluation rows and set
`submissions.status = submitted` (non-shadow jobs), so the next attempt
starts clean and `complete(done)` counts only its own results.

Every transition happens inside a transaction that locks the job row and
re-checks its state (§6.2 rule 1), the sweep's and the dial's included; a
request that fails the lease check (§6.2 rule 2) is `409 lost` and changes
nothing (T5).

| # | From → to | Trigger | Guard | Effects |
|---|---|---|---|---|
| T1 | — → `wait` | `add_judge_job`, dial routes to pool | — | in one transaction: `Job.supersede!` (4.7.2) moves the submission's older `wait` / `process` jobs to `error`; evaluations deleted; submission `submitted`; envelope built and stored; `current_job_id` := this job; `attempts` 0 |
| T2 | — → `wait` (shadow) | `ShadowGrading.enqueue` after a legacy T1 | submission selected by `judge.shadow_share` | own envelope; `shadow_gradings` row `pending` with `live_job_id`; submission untouched |
| T3 | `wait` → `process` | claim | `requires` ⊆ capabilities; worker not paused (manual or automatic); dataset not quarantined; worker not in `excluded_worker_ids`, or the job has waited 60 s since its last attempt (so a pool of one worker still retries); policy limits (§7.6) | `attempts` + 1; new `lease_token`; `lease_expires_at` = now + 120 s; `deadline_at` = now + ceiling; `judge_worker_id`; event `claimed` |
| T4 | `process` → `process` | progress, or a heartbeat pair | lease check | lease extended; events written once per `(job, attempt, seq)`; `compiled` sets the submission's compile fields; `testcase` upserts an evaluation (shadow: the shadow row) |
| T5 | `process` → unchanged | any request that fails the lease check | — | `409 lost`; nothing written; logged; the agent kills the runner |
| T6 | `process` → `success` | `complete(done)` | lease check; every snapshot testcase has a result; live testcase ids = snapshot ids | score from the snapshot; `set_grading_complete`; lease token kept so a repeated complete is a 200 no-op. Shadow: results into the shadow row, `graded`, diff if the live generation is final |
| T6a | `process` → unchanged | `complete(done)` with results missing | lease check | 422 with the missing ids; the agent reports `agent_exception` (T9) |
| T7 | `process` → `error` | `complete(done)` | lease check; live testcase ids ≠ snapshot ids | `result` "dataset changed during grading"; `add_judge_job` starts a new generation (T1) |
| T8 | `process` → `success` | `complete(compilation_error)` | lease check | the `compiled` event already set the submission; event `completed` |
| T9 | `process` → `wait` / `error` | failure report, **job** domain | lease check | worker added to `excluded_worker_ids`; clear the attempt; at the third attempt → `error`, submission `grader_error` (shadow: row `failed`) |
| T10 | `process` → `wait` | failure report, **worker** domain | lease check | `attempts` − 1 (not this job's fault); clear the attempt; the agent pauses itself, so no exclusion is needed |
| T11 | `process` → `wait` / `error` | failure report, **dataset** domain | lease check | dataset quarantined; `attempts` − 1; clear the attempt. Except a first `file_gone`: no quarantine; `error` and `add_judge_job` (T1), so the new generation's snapshot names files the server still holds; a `file_gone` from that new generation quarantines the dataset |
| T12 | `process` → `wait` / `error` | sweep: lease expired | dial still routes the submission to the pool (shadow: always) | clear the attempt; at the third attempt → `error`, submission `grader_error` (shadow: row `failed`) |
| T13 | `process` → `error` | sweep: lease expired | dial no longer routes to the pool | `result` "converted to legacy"; `add_judge_job` starts a legacy generation |
| T14 | `process` → `wait` / `error` | sweep: ceiling passed | — | as T9 with class `timeout`; job id listed `lost` in that worker's next heartbeat reply |
| T15 | `wait` → `error` | `JudgeRouting.reconcile!` after a dial change | row locked with `SKIP LOCKED` and still `wait` (a job claimed meanwhile is left to finish); non-shadow; dial no longer routes to the pool | `result` "converted to legacy"; `add_judge_job` starts a legacy generation |
| T16 | `wait` / `process` → `error` | rejudge: `add_judge_job` for the same submission | — | `Job.supersede!` (4.7.2) moves every waiting or processing job of the submission — pool, legacy and shadow — to `error`, "superseded by rejudge"; a `process` job's next request fails the lease check (T5); `shadow_gradings` rows of the old generation → `superseded` |
| T17 | `process` → `wait` | `release` | lease check | `attempts` − 1; clear the attempt |
| T18 | `error` → `wait` | Retry / Retry All | current generation; submission exists and is not `done` / `compilation_error` (`Job.split_retryable`, 4.7.2) | `attempts` 0; `excluded_worker_ids` cleared |
| T19 | (dataset) quarantined → released | *Release* on the Graders page | — | its waiting jobs become claimable again; audited |
| T20 | `success` / `error` → deleted | `Job.clean_old_job` | age (1 day / 30 days) | events deleted with the job |

What the table guarantees, and the review round 1 point each line closes:
a superseded job can never write the submission (T5, T16; point 2); a
retried request never writes twice (T4, T6; point 3); no `grade` job is
left without a path once the dial moves (T13, T15; point 4); a hung runner
ends at its ceiling (T14; point 5); a bad dataset stops itself, not the
workers (T11; point 6); a shadow job never touches the submission (T2, T6,
T12; point 1).

## 8. Legacy path during the transition

The legacy boxes and the pool share one `jobs` table and never see each
other's jobs. The agent may run on the same host as legacy boxes using box
ids the legacy watchdog does not manage (cp-worker: 9–16 are free). A server
without the judge API is simply absent from every agent's config and is
served by its own boxes as today. Phase 4 retires: `Grader` main loop and
watchdog, the cron entry, `worker_datasets`, `WorkerController`, the shared
passcode, and `GraderProcess` (kept read-only for one release for history).

### 8.1 What the legacy path already does (release 4.7.2)

Three hardening fixes shipped before phase 0 (revs 2251–2254, released as
4.7.2 on 2026-10-08). The pool keeps their behaviour, and they differ from
the design sketched in the handoff in the ways listed here.

- **Bounded checker and initializer** (rev 2251). `JudgeBase#run_bounded`
  runs a command in its own process group and kills the group at the
  deadline. A checker gets `JudgeBase::CHECKER_TIMEOUT` (30 s): on expiry
  the testcase gets `!` and the submission continues. A dataset initializer
  gets `INITIALIZER_TIMEOUT` (120 s): on expiry the submission gets a
  grading error and the `worker_datasets` row rolls back to `created` with
  its transaction, so the next job retries. Both can be overridden in
  `worker.yml` under `limits:`. The agent's per-phase deadlines (§9.6) use
  the same defaults.
- **Stuck-box watchdog** (rev 2251). `Grader.plan_box` kills a box's grader
  when its heartbeat is older than 600 s *and* the process is older than
  600 s, so a grader just respawned on a box with an old heartbeat
  survives.
- **Rejudge supersedes the running grading** (rev 2253). `add_judge_job`
  first calls `Job.supersede!`: the submission's waiting and processing
  jobs become `error`, "superseded by rejudge". The grader checks
  `Job.chain_current?` after it claims a job and again before every write
  (compiled binary and status, evaluation row, score, grading error). The
  chain check counts *every* row of a submission, not only compile rows —
  the chain id is the compile job's id, or `parent_job_id` for evaluate
  and score rows — because `Job.clean_old_job` deletes a successful compile
  row after a day but keeps the chain's error rows for 30, and "no newer
  compile job" alone would let a superseded error row look current again.
  The pool replaces the check with `current_job_id` (§6.2 rule 2); §7.3
  keeps the two in step.
- **One evaluation per submission and testcase** (rev 2253). The migration
  deleted the orphan rows and built the unique index; the evaluator writes
  `find_by || create_or_find_by!`, so a judge host deployed before its web
  host has migrated never creates a duplicate.
- **Retry guards** (rev 2252). Retry and Retry All re-queue a failed job
  only when its submission still exists, is not `done` or
  `compilation_error` (a newer chain finished, and its rows may all be
  gone), and the job's chain is current (`Job.split_retryable`); the toast
  counts the skipped jobs. Retry of a `grade` job uses the same guard with
  `current_job_id` (§7.8 T18). Clear All is unchanged.

None of the three sandboxes the checker; that is phase 0 slice 0.3 (§10).

## 9. Agent

Plain Ruby, no Rails. Lives in this repo under `judge_agent/` with its own
`Gemfile` (net/http, json, logger; no ActiveRecord) and shares the engine
library (§9.1). Same release tag as the web app; the protocol version is a
constant checked in the handshake.

### 9.1 Engine library (phase 0)

`lib/cafe_judge/` becomes a plain-Ruby library over the envelope: `Envelope`
(typed reader), `Compiler::*` (today's per-language classes, minus
ActiveRecord), `Evaluator`, `Checker`, `IsolateRunner`, `LanguageProfile`
(today's constants from `Problem#exec_filename`,
`JudgeBase#isolate_options_by_lang`, `#isolate_need_cg_by_lang`, overridable
by envelope values), and a `ResultSink` interface (`compiled`, `testcase`,
`done`, `failed`). `app/engine/*` becomes adapters: `EnvelopeBuilder` (AR →
envelope), `ActiveRecordSink` (today's writes), and the legacy `Grader` loop
calls the library. `Scorer` stays in the Rails app (it is DB arithmetic).
`engine:smoke` and `Replay::*` prove equivalence at every slice.

### 9.2 Process model

- **agent** (one per host, systemd `cafe-judge-agent.service`,
  `Restart=always`): threads for one claim loop per server, the heartbeat
  loop, the policy applier, the local scheduler, and the cache janitor.
- **runners**: forked children, one per box, bound to that box id for life,
  JSON-lines over a pipe pair. A runner executes one phase (compile or run of
  one or more testcases) and reports events back; the agent posts them. A
  runner crash is an infrastructure error for its job; the agent restarts
  the runner and cleans the box (`isolate --cleanup`).
- **SIGTERM** = drain: no new claims, finish running jobs (bounded by
  `drain_timeout_s`), release the rest, exit. **SIGHUP** = reload config
  (servers, tokens, weights) without dropping jobs.

### 9.3 Lanes, prefetch, local scheduling

```yaml
worker:
  runners: 8
  compile_lane: {share: 10%, min: 2}   # 8 runners → 2 compile, 6 run
  reserve_cores: 1
```

- The agent claims when it has an idle run-lane runner **or** when the
  compile lane is idle and the local backlog is below the **prefetch bound**
  (2 × compile-lane size). The bound keeps a host from holding leased jobs
  another host could run.
- A compile-lane runner compiles immediately and posts `compiled`. A compile
  error completes the job there, so students get it after one claim plus
  one compile regardless of the run backlog — today's compile-only boxes,
  without a job type.
- A successful compile queues the job locally for the run lane. The run lane
  takes one submission at a time per runner; when several run runners are
  idle, one submission's testcases spread across them (same binary on local
  disk), up to the server's `max_runners_per_job` (§7.6).
- **One scheduler owns the idle budget.** The claim loops do not claim on
  their own: each asks the scheduler how many jobs it may claim from its
  server now, and the scheduler counts idle runners, jobs already claimed
  but not started, and the prefetch bound across all servers at once. Two
  claim loops can therefore never both claim against the same idle runner
  (review round 1 point 9).
- **Weighted service across servers.** When jobs from several servers wait
  locally, the scheduler shares runner time between them in proportion to
  their weights (worker config), by deficit round robin over sandbox
  seconds (`cost.estimate_s`). A server with nothing waiting gives its
  share to the others. Revision 1 ordered by weight first, which let a
  busy high-weight server starve a low-weight one. Within one server, the
  order is job priority, then claim time.
- **Concurrency is counted in jobs.** A server's `max_concurrency` caps how
  many of its jobs are in any lane at once; `max_runners_per_job` caps how
  far one job spreads. Neither counts runners.
- **Memory is accounted per job.** Each running phase reserves its
  dataset's `memory_limit` per runner it uses (a compile reserves a fixed
  `compile_mb`, default 1,024). The scheduler starts a phase only while the
  reservations fit in host memory minus `reserve_mb` (default 2,048).
  Eight runners at 256 MB use a fraction of cp-worker's 32 GB, but eight
  runners on a dataset with a 4 GB limit would ask for all of it; the
  reservation makes the runners beyond 30 GB wait instead.
- **No preemption.** A running phase is never stopped for a higher-priority
  job; priority and weight only decide what starts next.
- **Small-job reserve** is the compile lane itself: jobs with
  `cost.estimate_s` below `small_job_s` (default 3 s) may run in the compile
  lane when the run lane is full, and only while no compile is waiting.
  Trivial submissions never queue behind long ones, and a compile that
  arrives waits at most for one small job to finish on its runner
  (revision 1 said compiles "never queue behind small runs", which a
  non-preemptive scheduler cannot promise).

### 9.4 Language handling

Phase 0 keeps the per-language compile classes in the library, keyed by
`language.name`, with `LanguageProfile` holding the constants the envelope
can override. Moving the constants into `languages` table columns and
building the envelope from them is the backlog item (issue #42), listed as
an optional slice in phase 1 (§12); the protocol does not change when it
lands.

### 9.5 Cache and job directories

```
/var/lib/cafe-judge/
  cache/sha256/ab/abcd…        # content-addressed files, immutable
  jobs/<server>/<job_id>/      # envelope.json, source/, bin/, tc/<n>/{meta,stdout,stderr}, agent.log
  init/<sha256-of-inputs>/     # PostgreSQL initializer workspaces (JudgeBase#run_initializer today)
```

- A job directory is built from the cache with hard links, so a dataset's
  files exist once per host regardless of how many jobs use them.
- The initializer workspace is keyed on the hash of all its inputs
  (initializer files + testcase files), so it is rebuilt exactly when any
  input changes.
- **PostgreSQL workspaces are namespaced** (review round 1 point 7). Today's
  initializer (`lib/templates/postgres/postgresql_initializer.rb`) and
  compiler (`app/engine/compiler/postgres.rb`) name tables by the bare
  testcase id (`<table>_<testcase_id>`), so two servers — or two datasets
  whose testcase ids collide — would overwrite each other's tables on a
  shared worker. Each workspace gets its own PostgreSQL schema,
  `cj_<server>_<first 12 hex of the workspace hash>`, and every statement
  of the initializer, the compile step and the run sets `search_path` to
  it. The per-testcase table renaming stays inside the schema. The janitor
  drops a schema with its workspace.
- Janitor: job dirs older than 24 h removed; cache trimmed LRU above
  `cache_max_gb` (default 20); disk below `low_disk_mb` (2,048, as
  `GraderProcess::LOW_DISK_MB`) pauses claims and is reported in the heartbeat.

### 9.6 Capabilities and admission

At start the agent detects: `lang:<name>` for every compiler path in config
that exists, `cg` if `isolate --cg --init` succeeds, `postgres` if
`postgres:` is configured, `net` if `allow_share_net: true`, `mem:<MB>` from
the host. It refuses to start with `runners > cores − reserve_cores`, and
pauses claims while the 1-minute load average exceeds `cores × 1.5` or disk
is low. `wall_slack_s` (default 0.5, today's constant in `IsolateRunner`) is
a config value so a VM with steal time can be given more slack without a
code change.

**Per-phase deadlines** (review round 1 point 5). The agent gives every
phase its own deadline and, at expiry, kills the runner's process group,
cleans the box and reports `timeout` with the phase — except an
initializer, which is reported as `initializer_failed` (a dataset fault,
§6.7), and a checker, which gives `!` on its testcase:

| Phase | Deadline |
|---|---|
| fetch | 60 s plus 1 s per MB still to download |
| init (dataset initializer) | `initializer_timeout_s`, default 120 s (as `JudgeBase::INITIALIZER_TIMEOUT`) |
| compile | the envelope's `language.compile_timeout_s` + 10 s |
| run, per testcase | isolate's own time and wall limits already bound it; the agent adds a backstop of wall limit × 2 + 5 s for an isolate that does not return |
| check, per testcase | `checker_timeout_s`, default 30 s (as `JudgeBase::CHECKER_TIMEOUT`); a checker timeout is a `!` on that testcase, not a job failure (§6.6) |

The server's ceiling (§6.4) sits above all of these, for the case where
the agent itself is what hangs.

### 9.7 Config file

`/etc/cafe-judge/agent.yml` (readable only by the agent's user
`cafe-judge`, §10; `agent.yml.SAMPLE` tracked, per the uppercase-SAMPLE
convention):

```yaml
worker:
  name: cp-worker-1
  runners: 8
  compile_lane: {share: 10%, min: 2}
  reserve_cores: 1
  judge_dir: /var/lib/cafe-judge
  isolate: /usr/local/bin/isolate
  wall_slack_s: 0.5
  small_job_s: 3
  cache_max_gb: 20
  compile_mb: 1024
  reserve_mb: 2048
  checker_timeout_s: 30
  initializer_timeout_s: 120
  compilers: {cpp: /usr/bin/g++, c: /usr/bin/gcc, python: /usr/bin/python3, java: /usr/bin/javac, …}
  # postgres: {host: 127.0.0.1, port: 5432, …}
  # allow_share_net: false
servers:
  - {name: cp-grader, url: https://grader.nattee.net/grader, token: "…", weight: 3}
  - {name: cedt,      url: http://10.0.5.80,                 token: "…", weight: 1}
```

Adding a server is one line; rotating a token is one value; both take
effect on SIGHUP.

### 9.8 Logs and CLI

- `log/agent.log`, rotated by size (10 × 50 MB); one `agent.log` per job
  directory, kept with it for 24 h. No single ever-growing judge log.
- `bin/cafe-judge`: `check` (config + capabilities, exit non-zero if the
  host cannot start), `status` (servers, runners, current jobs, last error
  per server), `job <server> <id>` (that job's log and artifacts), `replay
  <envelope.json>` (run a downloaded envelope locally with a null sink, the
  reproduction tool for failure reports), `drain`.

### 9.9 Failure classification

Each class belongs to one fault domain (§6.7); the domain decides what
stops.

| Condition | Class | Fault domain |
|---|---|---|
| compiler binary missing, `isolate` missing, `--cg` unsupported | `missing_compiler` | worker: the agent pauses itself for every server |
| `ENOSPC`, disk below threshold | `disk_full` | worker |
| isolate returns `XX` | `isolate_failed` | job; worker on the second within 10 minutes |
| uncaught exception in a runner or the agent's job handling, a runner crash | `agent_exception` | job; worker on the third within 10 minutes |
| a phase passes its deadline (§9.6), the server's ceiling passes | `timeout` | job |
| dataset initializer exits non-zero or times out | `initializer_failed` | dataset: quarantine |
| file endpoint answers 410 | `file_gone` | dataset: re-snapshot, then quarantine if it repeats |
| downloaded file does not match its hash, three times | `hash_mismatch` | dataset |
| envelope fails schema validation | `bad_envelope` | dataset |
| connection refused, timeout, 5xx, 429; any other fetch failure after 3 tries | `fetch_failed` | server or network: back off from that server |
| checker crashes or times out on one testcase | — | none: `!` on that testcase (§6.6) |
| compile error, RE, SG, TO, wrong answer, partial | **verdict** | submission; never an error |

### 9.10 Deployment

The automation repo gains a host role `worker`: checkout, `bundle install`
in `judge_agent/`, `cafe-judge check`, `systemctl restart
cafe-judge-agent`, then `cafe-judge replay` of a bundled sample envelope as
the smoke step (replaces `engine:smoke` on worker-only hosts). The per-host
`agent.yml` is created from `.SAMPLE` once and never overwritten.

## 10. Security

- One bearer token per worker × server pair, issued on the server, stored as
  a digest, shown once, revocable, audited. Scope: the judge API only. It is
  a grade-altering secret and is handled like the DB password.
- HTTPS wherever a server has it (grader.nattee.net via the proxy); plain
  HTTP only inside 10.0.5/24. The toi box on 10.24.0.0 must use HTTPS.
- The agent fetches files only from the issuing server's `base_url`, verifies
  `sha256` and size, and caps output files at 50 MB (today's `-f 50000`).
- The server validates every progress / complete against the job's lease
  token and worker id; a stale lease is 409 and logged.
- Per-worker claim rate limit (default 20/s) protects Passenger from a
  misconfigured agent.
- Student code runs in isolate exactly as today; per-server separation on
  the worker is by directory, and runners of different servers share the
  host, as today's boxes share it.
- Any authenticated worker may fetch any file the server holds by its hash;
  the files endpoint does not check that a leased job names the file. The
  token is already a grade-altering secret, so this adds no new trust.
- **Checkers and initializers run inside isolate** in the agent (phase 0
  slice 0.3): their own box, no network except the PostgreSQL connection
  an initializer needs (`--share-net`, only on a worker with the `postgres`
  capability), the job directory read-only apart from their output, and
  the deadlines of §9.6. The agent runs as its own unprivileged user
  `cafe-judge`; `agent.yml`, which holds every server's token, is readable
  by that user only, so nothing inside a box can read it. The legacy path
  gets the same sandbox in slice 0.3, with a `worker.yml` switch
  `checker_sandbox: false` kept for one release so a legacy host can fall
  back without a redeploy; the agent has no such switch. Slice 0.3 is
  proven by the replay test in the handoff (§4 there): every custom-checker
  and PostgreSQL dataset on the prod copy, 100 sampled submissions each,
  no difference beyond T→P and x→P.

**Trust domain.** Whoever can upload a checker or a dataset initializer can
run code on the judge host outside the student sandbox, as the user that
runs the grader. On cp-grader that is 18 admins and 39 enabled group
editors (§3). Today the reach is one server's judge host. On a pooled
worker it would be every server that worker serves: their cached testcases
and answers, their job directories and their tokens. Hence the order: no
pool worker serves any server before slice 0.3 ships, so the pooled
exposure never exists.

**Interim decision (dae, 2026-10-04): accept the exposure** on today's
per-server judge hosts until phase 0 ships sandboxed checkers. Uploads are
not restricted meanwhile (§15).

## 11. Testing

| Layer | Proves | Tool | Where |
|---|---|---|---|
| Contract | state machine of claim / progress / complete / release, lease expiry and sweep, idempotency, 426 on version, 401/409 paths | rswag spec → `swagger/judge/v1.yaml`, part of `bin/rails check`; the agent's suite runs against a stub server (small Rack app in `judge_agent/test/`) built from the same YAML | CI |
| Engine equivalence | library grades exactly as the in-process engine | `engine:smoke` and `Replay::ReplaySampler` + `ReplayDiff` run through both adapters; only T→P and x→P are benign. `ReplayDiff` today ignores points (review round 1 point 8; `engine:smoke`, the deploy gate, does compare them): slice 0.5 makes it compare points and per-testcase scores with one verdict vocabulary, and moves ahead of slice 0.3 so nothing relies on it first | local, prod copy |
| Agent unit | lanes, prefetch bound, one budget owner, weighted service, memory reservation, cache, failure classification by fault domain, per-phase deadlines, `lost` handling, config reload, drain | minitest in `judge_agent/test/`, isolate stubbed | CI |
| Stress | the ceiling and what breaks first | `judge:stress` rake task enqueues sampled past submissions as `grade` jobs at low priority; collect claim latency and throughput from `judge_job_events`, Passenger queue depth, MySQL load, and the CPU/wall ratio of every run | staging: grader-cp-backup 10.0.5.55 with a prod DB copy + a fresh worker VM |
| Shadow | real traffic, zero student impact | `judge.shadow_share` on cp-grader through at least one quiz; mismatches reviewed on the shadow card | production |
| Canary | real students, limited blast radius | `judge.pool_share` 10 → 50 → 100 on one server, a week each, legacy boxes still enabled | production |
| Soak | nothing missed | legacy boxes disabled, not deleted, for a term | production |

Stress targets from §3: sustain 60 submissions/min and burst 80/min for 10
minutes with claim latency flat; then raise until something gives, and
record what.

**Acceptance scenarios** (review round 1 point s4). Each is a contract test
against the server (rswag or an integration test) and, from phase 2, an
end-to-end run on staging with a real agent. Each names the §7.8
transitions it proves.

| Scenario | Expected |
|---|---|
| A `complete` reply is lost; the agent sends it again | second call 200, no second score, one `completed` event (T6) |
| Progress events arrive twice and out of order | each `(attempt, seq)` written once; every testcase ends with exactly one evaluation row (T4) |
| A job's lease expires, a second worker claims it, then the first worker's late progress arrives | late progress 409; nothing written; first worker kills its runner (T5, T12) |
| Rejudge while a pool job runs | old job `error` "superseded by rejudge"; its next request 409; new generation scores; no evaluation row from the old one survives (T16, T1) |
| Shadow job fails three times | shadow row `failed` with the report; submission and its evaluations untouched (T12, T2) |
| Testcase added to the live dataset while a job runs | complete starts a new generation instead of scoring (T7) |
| Checker replaced while a job waits | the waiting job still fetches the old checker by hash (24 h retention) and grades against its snapshot |
| Server restarts mid-job | the agent backs off, then posts; idempotent writes leave one copy of each event (T4) |
| Dial set to 0 with jobs waiting and jobs leased | waiting jobs converted to legacy at once; leased ones finish or are converted when their leases expire (T15, T13) |
| A runner hangs and the agent keeps renewing | the job ends at its ceiling, counted as a job fault (T14) |
| A dataset's initializer fails | dataset quarantined; no worker pauses; *Release* resumes its jobs (T11, T19) |
| Lease sweep stops running | health line red within 5 minutes |
| Cold cache: a new worker's first job on a dataset it has never seen | claim → `compiled` latency and fetch time recorded in the ledger for a typical (14 × 663 KB) and the largest dataset; the target is set from the measurement, and the fetch deadline (§9.6) must sit above the largest |

## 12. Phases and slices

Everything lands on `master` in releasable slices (dae, 2026-10-04): each
slice keeps `bin/rails check` and `engine:smoke` green and is either inert
behind the dial or verified by the replay diff. No feature bookmark; an
unfinished slice stays in a local bookmark or the clone workspace, never
pushed. Sizes are sessions of a few hours. Each phase gets its own
implementation plan under `docs/superpowers/plans/` and its own ledger; the
next phase's plan is written when the previous phase ships.

**Freeze windows:** no phase-0 slice deploys within 7 days before a quiz or
final; `judge.pool_share` and `judge.shadow_share` change only while no
contest is active on that server and never on an exam day.

| Phase / slice | Content | Size |
|---|---|---|
| **Pre-phase-0 hardening** — shipped in 4.7.2 (revs 2251–2254): bounded checker and initializer, stuck-box watchdog, rejudge supersede + chain check, unique evaluations, retry guards (§8.1) | | done |
| **0 — engine extraction** (standalone value: cleaner engine, sandboxed checkers, groundwork for issue #42). Slices in this order: 0.1, 0.2, 0.5, 0.3, 0.4 | | 3–4 weeks |
| 0.1 | `lib/cafe_judge/envelope.rb` + `EnvelopeBuilder` (AR → envelope) + JSON schema + builder tests | 1 |
| 0.2 | `Compiler::*` on the envelope; `ActiveRecordSink`; legacy `process_job_compile` through the library | 1–2 |
| 0.5 (before 0.3) | `ReplayDiff` compares points and per-testcase scores (§11); `engine:smoke` and `Replay::*` through the library; replay diff on 100 sampled submissions per language on the prod copy, recorded in the ledger | 1 |
| 0.3 | `Evaluator` + `Checker` + `IsolateRunner` on the envelope; legacy evaluate through the library; **checkers and initializers inside isolate** with the `checker_sandbox` fallback switch (§10), proven by the replay test of every custom-checker and PostgreSQL dataset and a fleet census of checker types | 3 |
| 0.4 | `LanguageProfile` registry replacing the scattered constants | 1 |
| **1 — server side** (standalone value: timeline + error card for legacy boxes too; tokens replace the passcode) | | 4–5 weeks |
| 1.1 | `judge_workers` table, model, token page with rotation (two digests), audit actions | 1 |
| 1.2 | `jobs` columns incl. `envelope` and `deadline_at`, `grade` kind, legacy exclusion and `grade` as a chain start (§7.3), `submissions.current_job_id`, dial keys, routing in `add_judge_job`, `JudgeRouting.reconcile!` | 1–2 |
| 1.3 | judge API: heartbeat with `{job_id, lease}` pairs + policy, two-step claim, files by hash; `blob_digests` + backfill; 24 h file retention | 2 |
| 1.4 | progress + complete + failure report under the rules of §6.2; server-side scoring from the snapshot; `judge_lease_sweep` (1 minute, ceiling); `judge_job_events`, also written by the legacy `take_oldest_waiting_job` / `Job#report` (`claimed`, `completed`), so the timeline covers legacy boxes from this slice on; contract tests for every §7.8 transition | 2–3 |
| 1.5 | Graders page: Judge Workers card (manual and automatic pause), health line, job timeline, failure detail, envelope download | 2 |
| 1.5a | fault domains on the server: `excluded_worker_ids`, dataset quarantine and *Release*, the quarantine list on the Graders page | 1 |
| 1.6 | shadow mode: separate enqueue (`ShadowGrading.enqueue`), `shadow_gradings`, diff when both are final, shadow card | 1 |
| 1.7 | rswag spec + `swagger/judge/v1.yaml` + `/api-docs` entry + `doc/Judge-Worker-Pool.md` | 1 |
| 1.8 (optional, issue #42) | `languages` columns for the profile values; builder reads them | 1–2 |
| **2 — agent** | | 4–6 weeks |
| 2.1 | skeleton, config, capabilities detection, `cafe-judge check` | 1 |
| 2.2 | HTTP client, claim loops, heartbeat + policy applier, version handshake | 1–2 |
| 2.3 | runners (fork), box lifecycle, pipe protocol, crash recovery | 2 |
| 2.4 | cache by hash, job directories, initializer workspace with its own PostgreSQL schema (§9.5), janitor | 1–2 |
| 2.5 | lanes, prefetch bound, one scheduler owning the idle budget, weighted service, memory reservation, small-job reserve | 2 |
| 2.6 | failure classification by fault domain, automatic pause and backoff, per-phase deadlines, per-job logs, `status` / `job` / `replay` CLI | 1–2 |
| 2.7 | systemd unit, drain/reload, deploy role in the automation repo | 1 |
| 2.8 | stub server + contract tests; agent unit tests | 2 |
| 2.9 | `judge:stress` task; staging run on .55 + worker VM; the acceptance scenarios of §11 end to end; results in the ledger | 2–3 |
| **3 — shadow** on cp-grader through one quiz | calendar-bound | — |
| **4 — canary, cutover, soak, retire** | dial 10 → 50 → 100 per server; legacy disabled a term; then remove `Grader` loop/watchdog/cron, `worker_datasets`, `WorkerController`, passcode; `GraderProcess` read-only one release, then dropped | 1–2 for the retire slices |

**Rollback at any point:** dial to 0 (waiting `grade` jobs are converted at
once, leased ones finish or are converted when their leases expire; §7.8
T13, T15), pause the worker on the server's page, or stop the agent
service (leases expire within 2 minutes and the 1-minute sweep converts or
re-queues them).

## 13. Documentation to keep current

- `doc/Judge-Worker-Pool.md` (new, phase 1.7): operator reference — protocol
  summary, config file, page controls, failure classes, runbook.
- `CHANGELOG.md`: user- and operator-facing slices (token page, dial keys,
  page cards, the agent) in the commit that lands them.
- `doc/backlog.md`: issue #42 entry points here; the deferred items in §14
  get entries when they are deferred.
- `CLAUDE.md` Background Processing section: one paragraph once phase 2
  ships.

## 14. Deferred, with the condition to reopen

| Item | Reopen when |
|---|---|
| Central broker (approach C) with a fleet dashboard | the server × worker config matrix or cross-server priority becomes a recurring operator chore |
| Server → worker wake-up nudge | measured idle polling load on Passenger matters; `poll_ms` in the policy is the first lever |
| isolate box reuse across testcases of one submission (init once, run many) | profiling shows isolate init/cleanup dominates short testcases |
| Proportional wall slack (e.g. `max(2×, +1 s)`) | false timeouts appear on a worker that cannot be given dedicated cores |
| Storing testcase outputs for the timeline | a diagnosis needs them; `evaluations.output` exists unused |
| Preemption of a running phase for a higher-priority job | a measured case where exam compiles wait behind long runs despite the compile lane |
| Files endpoint serving only hashes named by a job leased to the asking worker | workers are no longer all trusted alike (e.g. a worker run by another department) |
| Legacy chain check reading `submissions.current_job_id` instead of job rows | the legacy path outlives phase 4's schedule; until then the two checks are kept in step (§7.3) |

## 15. Decision log

- **2026-10-03** — Approach B over A and C (dae). B's envelope and lease are
  designed so C is a drop-in.
- **2026-10-03** — Wire unit is one submission; per-testcase parallelism is
  internal to the host. Reason: no binary round trip, no fan-in on the
  wire, lanes recover the compile-first behaviour.
- **2026-10-03** — Scoring moves server-side. Reason: DB arithmetic, no
  sandbox; removes the score job's queue wait.
- **2026-10-03** — Root cause of the 2024–25 "more boxes = slower" memory is
  the missing `jobs.status` index, fixed 2026-09-08; B makes it structurally
  impossible to regress (pollers = hosts, batch claim, one indexed statement).
- **2026-10-04** — Lanes (compile share + minimum) replace the per-box
  job-type filter; capabilities replace manual routing; pause / concurrency /
  kinds live on the server's page, trust and host facts in the worker file.
- **2026-10-04** — Failure report and event timeline are protocol objects;
  infrastructure errors pause the worker and re-enqueue elsewhere; verdicts
  never reach the error card.
- **2026-10-04** — All work on `master` in releasable slices, no feature
  bookmark; freeze windows around exams; phases ordered so each has
  standalone value if the project pauses.
  *Reason* (added 2026-11-19: the entry had none, and dae asked why the
  rule exists while weighing a `judge-pool` bookmark; the rule was kept):
  1. A branch adds no protection. Each slice is safe on `master` without
     one: inert while `judge.pool_share` is 0 % (phase 1; the phase-2
     agent in `judge_agent/` is never loaded by the web app), or proven by
     the replay diff before it lands (phase 0). The same code reaches the
     fleet when it merges either way.
  2. A long-lived pushed bookmark drifts. During the pause from 2026-10-10
     to 2026-11-19 `master` changed `app/engine/` in six commits (revs
     2278–2286); a bookmark would have had to merge through the very files
     phase 0 rewrites. On `master` a finished phase keeps its value when
     the project pauses.
  3. The repository rule that every commit lands on `master` (CLAUDE.md)
     exists because commits made off `master` had to be grafted back and
     stripped, in 2026-05 and again 2026-07-21.
  Unfinished work lives in a local bookmark or the clone workspace, one
  slice at a time, never pushed.
- **2026-10-04** — **Interim trust: accept the exposure** (dae). Custom
  checkers and dataset initializers keep running unsandboxed on today's
  per-server judge hosts until phase 0 ships sandboxed checkers; no upload
  restriction meanwhile (handoff §6). What bounds it: today each judge host
  serves one server, and no pool worker serves any server before slice
  0.3, so the exposure never extends across servers (§10).
- **2026-10-04** — Review round 1 (independent session; every citation
  verified against the code and the prod copy): nine main points and four
  smaller ones; eight of the nine real, the ninth partly. Outcomes in
  `doc/judge-worker-handoff-2026-10-04.md` §2; revision 2 (2026-10-08)
  folds them in as the entries below.
- **2026-10-08** — **Generation = job id** (point 2). `submissions.current_job_id`
  names the current generation; only it may write the submission. The
  envelope is stored on the job at enqueue, and scoring reads that snapshot,
  not the live dataset. A changed set of testcases starts a new generation
  instead of scoring (§6.3, §7.4, §7.8 T7). The legacy path keeps its
  job-row chain check from 4.7.2; slice 1.2 makes `grade` rows start a
  chain so the two checks agree (§7.3).
- **2026-10-08** — **Five protocol rules** (point 3): heartbeat renews by
  `{job_id, lease}` pair; `seq` unique per `(job, attempt)`; `complete(done)`
  refused until every snapshot testcase has a result; lease check, writes
  and state change in one transaction with the job row locked; `409 lost`
  makes the agent kill the runner (§6.2).
- **2026-10-08** — **Shadow has its own enqueue, retries and storage**
  (point 1); it never goes through `add_judge_job`, and the diff runs when
  both gradings are final (§7.2).
- **2026-10-08** — **The sweep no longer re-routes everything** (point 4).
  An expired lease returns the job as the same generation; only a job the
  dial no longer routes to the pool is converted. A dial change converts
  waiting jobs at once (`JudgeRouting.reconcile!`). The sweep runs every
  minute instead of every 10, and its silence shows on the Graders page,
  because the 4.7.3 finding showed a recurring task can stop on every host
  without a sound (§3, §6.4, §7.5). Retry All re-queues only current
  generations (shipped for the legacy path in 4.7.2).
- **2026-10-08** — **Deadlines on both sides** (point 5): per-phase
  deadlines in the agent with the 4.7.2 defaults (checker 30 s,
  initializer 120 s); a server-side ceiling per attempt of
  `cost.estimate_s × 3 + 60 s` as round 1 decided, plus allowances for
  compile, initializer and a cold-cache fetch (§2 "ceiling", §6.4, §9.6).
  The allowances are new in revision 2: without them a PostgreSQL dataset
  whose initializer legitimately takes 120 s would pass a 14-testcase
  job's 102 s ceiling.
- **2026-10-08** — **Three fault domains plus the server/network one**
  (point 6): a job fault retries elsewhere; a dataset fault quarantines the
  dataset; a worker fault pauses that worker everywhere; a server or
  network fault backs off from that server. Manual and automatic pause are
  separate flags (§6.7). Revision 1 paused the worker for each failure,
  so one bad dataset would have paused every worker in turn.
- **2026-10-08** — **Checkers and initializers in isolate, PostgreSQL
  namespaced** (point 7): checkers and initializers move into isolate in
  slice 0.3, proven by the full replay test; the agent runs as its own
  user and nothing in a box can read `agent.yml`; each PostgreSQL workspace
  gets its own schema (§9.5, §10).
- **2026-10-08** — **`ReplayDiff` compares points before anything relies
  on it** (point 8): slice 0.5 moves ahead of 0.3 (§11, §12).
- **2026-10-08** — **Scheduling** (point 9): one scheduler owns the idle
  budget; weighted service by deficit round robin replaces weight-first
  ordering, which starved low weights; concurrency is counted in jobs,
  with `max_runners_per_job` capping spread; memory is reserved per job
  from its limit; no preemption, stated (§9.3).
- **2026-10-08** — **Smaller points**: SHA-256 per blob in
  `blob_digests`, and every file a snapshot can name is purged 24 h after
  it is detached instead of at once (s1 — the round-1 note said "kept while
  jobs reference them"; a fixed 24 h, the longest a job can wait, does that
  without reference counting, and `410 Gone` re-snapshots anything that
  slips past); a two-step claim, so a locking read never scans rows the
  capability filter skips (s2); token rotation with two digests and
  `rotate_token` audit rows (s3); the acceptance scenarios of §11 (s4).
- **2026-10-08** — **State-transition table, server side only** (round 1
  asked for one before phase 0): §7.8. Agent-side states wait for the
  phase 2 plan.
- **2026-10-08** — **Pre-phase-0 hardening shipped** as 4.7.2 (revs
  2251–2254); where the code differs from the handoff's sketch it is
  recorded in §8.1, and the pool keeps the same behaviour.
