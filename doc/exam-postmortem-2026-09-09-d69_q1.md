# DS Quiz 1 (`d69_q1`, 2026-09-09) — post-exam analysis and work queue

**Status: analysis DONE, decisions OPEN, no code changed.** Written 2026-09-12 from a Claude Code session that may be
interrupted; this file is the hand-off. Anyone (human or a later session) resumes from here — nothing in this document
lives only in a chat transcript.

## How to resume

- **Data.** The local dev DB (`grader`) was refreshed from 10.0.5.50 on 2026-09-12 17:56 (all small tables replaced,
  `submissions`/`evaluations`/`testcases` appended by id delta). Prod's Solid Queue job history is in the local `grader`
  DB as `prod_solid_queue_jobs` / `prod_solid_queue_failed_executions` (drop when done). Local backup of the replaced
  `users`/`grader_configurations` rows was taken to the session scratchpad only.
- **Readable views** (same folder): `ai-usage-d69_q1.html` — throwaway prototype of the proposed W1 report rendered from the
  local DB (tiles, two charts, wait distribution, per-model, per-session, every call); `review.html` — the 30 second-opinion
  sessions with rubric, both narratives and transcript. Rebuild with `render_ai_usage.rb` / `render_review.rb` via `bin/rails runner`.
- **Working files** (student data, so in course-prep, uncommitted at time of writing):
  `course-prep/data-structures/viva/quiz-2569-1-postmortem-2026-09-12/` — read-only prod probes `probe2..6.rb`
  (`bin/rails runner /dev/stdin` over ssh), local analyses `assist_local.rb`, `viva_outliers_local.rb`, the dry
  second-opinion pilot `dry_grade_pilot.rb` and its output `second-opinion-claude-opus-4-5.jsonl` / `.csv`.
- **Prod state.** grader-2023 at chula_cp 2144, working copy clean, site back in `standard` mode.
- **Decisions dae has to make** are in the numbered list at the end. Work items are listed with status; none started.

## The exam in numbers

Contest 43 `d69_q1`, 2026-09-09 09:30–11:20 Bangkok (stop extended from 11:00 at 10:45), 175 enrolled (169 students +
6 staff/test accounts). Problems: 705 `d69_v1_cell_detection` (viva), 706 `d69_q1a_horse_training`, 707 `d69_q1a_popcorn`
(coding, assist allowed via `contests_problems.allow_llm`, 10 points per request).

| | count |
|---|---|
| viva sessions opened (705) | 161 by 158 students |
| graded | 151 (144 answered at least once; 7 graded 0 with no answer, by the 09-09 regrade tool) |
| opened, never answered | 17 sessions: 7 opened before 10:15 with the greeting in 6–10 s and still never answered (graded 0); 8 by the 7 queue-hit students of F2 (ungraded); 2 peeks by students who then answered |
| enrolled, never opened the viva | 17 (4 real students who did submit code: 2235, 2161, 2254, 2217) |
| viva model turns | 1042 (gemini-3.7-flash), cost USD 4.62 |
| viva grades in-exam / total | 87 in-exam, 151 total, cost USD 1.57 |
| assist requests | 260 by 109 students (opus 82, gemini-3.1-pro 77, Claude-Sonnet 53, flash 48) |
| assist dollars known | opus USD 8.57, flash USD 0.51; Genie relay models unpriced |
| code submissions | 706: 707 subs / 126 students; 707: 384 / 101 |

## Findings

### F1. One 3-thread job worker saturated from 10:19 (root cause of everything below)

`config/queue.yml`: one worker, `queues: "*"`, `threads: 3`, `JOB_CONCURRENCY` unset → 3 concurrent jobs for viva turns,
viva grades, assists and recurring tasks together. Unloaded a turn takes 4–6 s and an assist 15–35 s. From 10:19 assist
arrivals rose to 13–23 per 5 min and every call queued behind the others. Wait = `updated_at − created_at` on the
placeholder row (equal to Solid Queue `finished_at − created_at`, verified).

| call | n | mean | p50 | p95 | max |
|---|---|---|---|---|---|
| viva turn | 1042 | 98 s | 56 s | 358 s | 461 s |
| assist | 260 | 195 s | 157 s | 457 s | 497 s |
| viva grade (in-exam) | 87 | 170 s | 122 s | 449 s | 461 s |

48% of viva turns waited over 60 s. Two peaks: 10:22–10:55 (100–270 s) and 11:03–11:21 (climbing to 450 s).

### F2. Seven active students never got to answer the viva

They opened it, waited 92–454 s for the greeting, and never answered → viva 0. All were submitting code at the time.
Seven *other* students opened before 10:15, got the greeting within 6–10 s and never answered either — not queue
victims; they are listed in the prototype page's "never answered" table.

| student | opened | greeting wait |
|---|---|---|
| A | 10:26:58 | 125 s |
| B | 10:37:18, 11:15:58 | 131 s, 422 s |
| C | 10:40:34 | 146 s |
| D | 10:44:24 | 93 s |
| E | 10:45:41 | 120 s |
| F | 11:13:01 | 298 s |
| G | 11:19:56 | 454 s |

Who A–G are (and the seven others) is kept in the private course-prep repo,
`data-structures/viva/quiz-2569-1-postmortem-2026-09-12/students.md` — this repo is public (CLAUDE.md, "User data stays
out of this repo").

### F3. Failed turns: none in the exam

`viva_turns.status = error`: 0 rows in the window; `solid_queue_failed_executions`: 0 in the window. Two gateway 500s hit
practice sessions on 2026-09-10 (turns 8543, 8553); both recovered via Retry.

### F4. Retake / daily limit

- No contest-level retake limit exists (Phase B, `contest_problems.viva_retakes`, unshipped — `doc/Viva-Exam.md`).
- Problem 705 `viva_daily_limit`: 0 → 5 on 09-08, **5 → 1 at 09:38:48 on exam day by hand** (audit row on Problem 705).
- Counting is engaged-only (`VivaSessionsController#engaged_starts_today`): a session counts once it has a student turn.
  It held — 0 students with two answered sessions. Three students (2223, 2243, 2160) peeked, restarted and started again;
  the scenario text is identical every session, so nothing was gained.
- Side effect: `viva_daily_limit = 0` ("contest only") means *unlimited* starts in contest mode — that is why 5 and then 1
  were used instead.
- Prod lacks the `viva.practice_daily_start_limit` config key → problems with a nil limit fall back to the hard-coded 3.

### F5. 65 sessions were still open at exam end and were finalised by hand

Graded sessions ended by: student End button 22, interviewer `[[VIVA_DONE]]` ≈ 64, **left open 65**. The 65 were
finalised by 62 `POST /submissions/N/rejudge` requests between 13:28 and 14:04 (Passenger log), i.e. Re-run grading
clicked one session at a time. There is no "contest stopped → finish open viva sessions" step.

### F6. Bugs

| # | where | what | evidence | fix |
|---|---|---|---|---|
| B1 | `app/views/layouts/_header.html.haml:17` | 500 on every page for a logged-in user whose `session[:contest_id]` is an enabled contest they are not enrolled in (`@current_contest_user` nil) | 2 hits 09:39 from 161.200.189.92 | nil-guard (`&.extra_time_second.to_i`), same for `main/_contest_box.html.haml:28-29`; test |
| B2 | `app/views/report/_score_table.html.haml:4` + `Problem.contests_editable_problems_for_user` | in contest mode the report scope is a joined `DISTINCT` relation; `.order(:date_added)` then `problems.ids` → MySQL 8 "ORDER BY not in SELECT list … incompatible with DISTINCT". Reproduced locally. | 4 hits 10:30–11:56 from staff IPs | `reorder(nil)` before `.ids`, or make the contest scopes return the `Problem.where(id: …)` subquery form like `group_reportable_by_user` |
| B3 | `VivaTurn.fail_stale!` (`app/models/viva_turn.rb`) | marks a `processing` turn failed after 10 min by `updated_at`, which for a *queued* placeholder is its creation time — cannot tell queued from running. Max wait was 7.7 min; a busier exam shows students false "timed out" errors and a Retry that double-runs the call | latent | key on `llm_started_at` (see W2) and skip turns whose job is still in `solid_queue_ready_executions` |
| B4 | `ContestsController#set_system_mode` | gated by `group_editor_authorization` only → any group editor can flip the whole site's mode. TA account 2262 (editor of groups 31, 37, no admin role) switched to contest mode at 13:05 | audit row | `admin_authorization` on `set_system_mode` (and review `contest_action`) |

### F7. Viva grading check

- Cell Detection was regraded 2026-09-09 under a never-lower rule (`doc/Viva-History.md`). Free checks on the result look
  sane: score vs answer length correlation 0.55; all 7 zero-answer sessions = 0; rubric criteria spread 0–max.
- **Dry second-opinion pilot**, claude-opus-4-5 via the Chula AI Gateway, 30 sessions (12 flagged under-scored, 8 flagged
  over-scored, 10 spread), nothing written (rolled-back transaction), USD 2.03, 8 s/grade:

| group | n | flash mean | opus mean | mean change |
|---|---|---|---|---|
| under-scored candidates | 12 | 28.8 | 24.8 | −4.0 |
| over-scored candidates | 8 | 92.4 | 77.6 | −14.8 |
| spread | 10 | 55.0 | 41.4 | −13.6 |

  Opus lower on 25/30, higher on 4, SD of the difference 10.6, 18/30 within ±10. Systematically stricter (≈ 11 points),
  not noise. Largest gap 953381: one answer, 85 → 35. Whether Flash was lenient or Opus harsh needs a human read of the
  largest gaps (`second-opinion-summary.csv`). Full cohort dry pass ≈ USD 11, 25 min.

### F8. Assist during the exam

| model | requests | resubmitted after | improved | reached 100 |
|---|---|---|---|---|
| claude-opus-4-5 | 82 | 74% | 39% | 13% |
| gemini-3.1-pro | 77 | 74% | 49% | 11% |
| Claude-Sonnet | 53 | 79% | 36% | 2% |
| gemini-3.7-flash | 48 | 63% | 50% | 7% |

Per student-problem pair (133): gain > penalty 33, equal 3, **worse off 97** (84 gained nothing). Assist users' mean best
score was lower on both problems (706: 30.9 vs 47.9; 707: 27.6 vs 53.4) — mostly who asks, not what the hint does.
58 of the 75 requests in the last ten minutes got no follow-up submission. Nine students paid ≥ 50 points on one problem
for no gain. Score at request time was under 25 for 228 of 260 requests.

## Proposed work (none started; W1 is the design awaiting approval)

- **W0 — queue split (do first, deploy before the next exam).** `config/queue.yml`: a `viva` queue with its own worker
  (≈ 8 threads) for `Llm::VivaTurnAssistJob` / `Llm::VivaGradeAssistJob` (`queue_as :viva`), assists on `default` with
  their own worker, recurring tasks unaffected; raise the DB pool to cover the threads. Config + one line per job class.
- **W1 — contest AI-usage report (bounded).** `GET /contests/:id/ai_usage` (+ `POST ai_usage_query`), button beside
  Watch/Edit on `contests/show`, same window/offset logic as `Contest#submissions`. Summary tiles (viva opened / answered /
  graded / never answered; assist requests / students / points / dollars), 5-minute timeline chart of arrivals vs mean
  wait (Chart.js as in `_score_table`), per-problem tables, per-request DataTable (student, problem, kind, model, queued s,
  model s, tokens, cost, status, link) with mean / p50 / p95 / max. Driven from `viva_turns`, `viva_grades`, `comments`
  directly (not Solid Queue rows). Small percentile helper beside `SubmissionRepair.median`.
- **W2 — timing columns.** `llm_started_at` on `viva_turns`, `comments`, `viva_grades`, stamped when the job starts, so
  queue wait and model time separate from now on; old rows show the total only. Also the basis for B3.
- **W3 — bug fixes B1, B2, B4** (small, with regression tests).
- **Deferred to `doc/backlog.md`:** contest-stop auto-finish of open viva sessions (F5); grade history (already there).

## Decisions for dae (OPEN as of 2026-09-12)

1. **W1 design** — approve as written, or say what to drop. No university quota involved.
2. **W0 before W1** — recommended; it is the cause of F1/F2 and needs a deploy.
3. **Second opinion** — a) stop here; b) full dry Opus pass (≈ USD 11, no writes, per-student comparison); c) read the six
   largest gaps in `second-opinion-summary.csv` first. Recommendation: c, then decide b.
4. **The seven students in F2** — makeup or not is a course decision. **DECIDED 2026-09-25 (dae):** no separate
   makeup; remedy = each student's Quiz 1 viva score becomes max(Quiz 1 viva, Quiz 2 viva), for **everyone who opened
   the Quiz 1 viva** (157 students; not the 17 enrolled who never opened it). Announced as a rule, so no list of names is
   published. Why everyone rather than a wait threshold: from 10:20 the next question took ~2–5 min for anyone still in
   the viva (worst normal wait before then 37 s); a "longest single wait ≥ 60 s" rule catches 129 and is flat to 2 min
   (124), so only ~28 were never hit, and the max() never lowers a score. Counts per boundary (longest single wait /
   total wait): 60 s 129/135, 90 s 125/129, 2 min 124/126, 3 min 109/119, 5 min 70/111, 10 min 0/86 — from
   `viva_turns` (assistant turn `updated_at − created_at`), local prod copy.
5. **Confirm** the 62 Re-run grading clicks (13:28–14:04) were yours, and whether the TA's mode flip (F6/B4) was intended.
6. **Housekeeping** — keep or drop the `prod_solid_queue_*` tables in the local dev DB.

## Status update — 2026-09-12 (built)

Plan `docs/superpowers/plans/2026-09-12-contest-ai-usage-and-queue.md` executed on master; full minitest suite green (1111 tests, 0 failures). Reviewed by dae 2026-09-13; merged to chula_cp and PUSHED (chula_cp 2145, then 2147/2149/2152 for the follow-ups). Deployed by dae via the GitLab pipeline; deployed with chula_cp 2158 — verified live on cp-grader 2026-09-21 and ise-grader 2026-09-22 (`hg id` on the hosts); other hosts unverified. No host step was needed.

| item | status | rev |
|---|---|---|
| W0 dedicated viva queue+worker | DONE; defaults 3+3 threads fit the stock pool of 5, deploy needs NO host env change (per-host tuning: `VIVA_JOB_THREADS`/`JOB_THREADS` + `RAILS_MAX_THREADS` in a queue env file) | 2137, 2146 |
| W1 contest AI-usage report | DONE (page + charts + per-call table; screenshot reviewed) | 2140, 2141 |
| W2 per-call timing columns | DONE | 2135, 2136 |
| B1 header/contest-box 500 | DONE | 2139 |
| B2 contest-mode report 500 | DONE | 2138 |
| B3 stale sweeper queued-vs-running | DONE | 2142 |
| B4 admin-only site-mode switch | DONE | 2141 |
| chart double-draw fix (found in review) | DONE | 2143 |
| worker defaults resized 5+3 → 3+3, knobs renamed `VIVA_JOB_THREADS`/`JOB_THREADS` (stock `JOB_CONCURRENCY` = processes) | DONE — deploy needs no host step | 2146 |
| `database.yml.SAMPLE` sizing note (threads <= pool − 1) | DONE | 2148 |
| config layering: `queue.yml` = defaults, `config/solid_queue.env` = per-host override (`.SAMPLE` shipped, real file ignored) | DONE in repo; on cp-grader (10.0.5.50) since 2026-09-25 via a systemd drop-in `solid_queue.service.d/env.conf` (`EnvironmentFile=-…/config/solid_queue.env`: `VIVA_JOB_THREADS=5`, `RAILS_MAX_THREADS=8`, for DS Quiz 2; verified `thread_pool_size` 5 viva / 3 default). No other host has it. | 2150 |
| Job Workers card on /grader_processes (effective queues + thread pools, stale rows red) | DONE (screenshot reviewed) | 2151 |
| F5 contest-stop auto-finish of open vivas | deferred to `doc/backlog.md` | — |

Decision 2 (deploy) is DONE — see above. Still open (dae): 3 (full second-opinion pass), 4 (makeup for the seven queue-hit students), 5 (confirm the 62 Re-run clicks + the TA mode flip), 6 (drop the local `prod_solid_queue_*` tables when done).
