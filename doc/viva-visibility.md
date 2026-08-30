# Viva Visibility & Scoring Reference

Who can see a viva transcript and grade, what problem material a student can
see, how the score is computed, and who's allowed to start a session — with
the code that enforces each rule. Audience: developers extending this area,
and the instructor deciding how to configure a viva problem.

For the full authoring/lifecycle picture, see `doc/Viva-Exam.md`. For the
current retake/limit policy and what's still unbuilt, see
`docs/superpowers/specs/2026-07-21-viva-context-policy-design.md` (Phase A
shipped; Phase B — per-contest retake budgets, window-end enforcement — has
not).

---

## 1. Transcript & grade visibility

A viva's transcript, turns, and grade are all reached through one gate:
`User#can_view_submission?` (`app/models/user.rb:458-499`), reused as-is from
ordinary code submissions — `VivaSessionsController#show`/`#refresh` call it
via `authorize_viva_view` (`app/controllers/viva_sessions_controller.rb:345-355`),
and the same predicate backs `SubmissionAuthorization#can_view_submission`
(`app/controllers/concerns/submission_authorization.rb`) used by the regular
submission-show flow. **The checks run in this fixed order**, and it matters:

```ruby
def can_view_submission?(submission)
  return true if admin?
  return true if problems_for_action(:report).include? submission.problem
  return false unless problems_for_action(:submit).include? submission.problem
  return true if submission.user == self
  return false if submission.viva_archived_at.present?
  return false unless GraderConfiguration["right.user_view_submission"]
  return submission.problem.view_submission
end
```

The `problems_for_action(:submit)` gate sits **before** the owner check — so
it applies to owners too, not just peers.

### Matrix

| Viewer | Problem in viewer's current `problems_for_action(:submit)`? | Session archived? | `right.user_view_submission` | Problem's `view_submission` | Result |
|---|---|---|---|---|---|
| Admin | — | — | — | — | **Yes**, always |
| Reporter (`problems_for_action(:report)` includes the problem) | — | — | — | — | **Yes**, always |
| Owner | **No** | — | — | — | **No** — redirected with an authorization alert |
| Owner | Yes | archived or not | — | — | **Yes** |
| Peer student | Yes | **archived** | — | — | **No**, always |
| Peer student | Yes | not archived | `false` | — | **No** |
| Peer student | Yes | not archived | `true` | `false` | **No** |
| Peer student | Yes | not archived | `true` | `true` | **Yes** |

### Notes

- **Peers never see an archived viva attempt**, even when the problem's
  `view_submission` would otherwise let students read each other's
  transcripts. The archived check (`user.rb:467`) is placed after the
  owner/admin/reporter short-circuits and before the `view_submission`
  check, so it only ever bites the "other student" path — an owner or staff
  member can always see their own or any archived session.
- **The owner can lose access to their own out-of-contest sessions while
  contest mode is on — this is intended, and symmetric with code
  submissions.** `problems_for_action(:submit)` is contest-mode-aware
  (`user.rb:95-130`): when `GraderConfiguration.contest_mode?` is true, it
  resolves to `Problem.contests_problems_for_user` (`problem.rb:137-148`),
  which requires the user to be **currently, actively enrolled in a contest
  window that includes this problem right now** (start/stop with per-user
  offsets, contest and enrollment both enabled). A viva started outside any
  contest (practice) fails that test the moment contest mode is switched on
  site-wide and the student isn't presently inside a qualifying window —
  `can_view_submission?` returns `false` for the owner before it ever
  reaches the owner check, and `authorize_viva_view` redirects them with an
  authorization alert. This is not viva-specific: it's the general
  submission-visibility rule (`SubmissionAuthorization`) applied to viva
  submissions too, exactly as it already applies to ordinary code
  submissions. It resolves itself the moment the student is back in a
  qualifying window (or contest mode is off again) — nothing about the
  submission itself changes.
- Separately (see §3), the student's **main list** (`/main/list`) also stops
  surfacing an out-of-contest viva as the canonical "current" session while
  contest mode is on, and its score drops out of the max-score aggregate
  shown there — a *display* effect on top of the *access* effect above, using
  the same contest-mode-aware scoping.

---

## 2. Problem-material visibility for viva

| Material | Visible to students? | Mechanism | Code |
|---|---|---|---|
| Statement PDF (`problem.statement`) | **No** | `Problem#pdf_visible_to_student?` returns `false` whenever `viva_exam?`; the download affordance and API `file` action gate on `User#can_view_problem_pdf?`, which consults it (instructors/reporters bypass) | `problem.rb:197-205`, `user.rb:428-444` |
| Description / Scenario (`problem.description`) | **No — never rendered to students in any view** | Used only as LLM input (`scenario_message` in `Llm::VivaTurnAssist#scenario_message` (`app/services/llm/viva_turn_assist.rb:103`) and `Llm::VivaGradeAssist#scenario_message` (`app/services/llm/viva_grade_assist.rb:46`)); no HAML template renders `problem.description` to a student for any problem, and vivas additionally skip the auto-generated-PDF path (`should_generate_pdf?` returns `false` for `viva_exam?`, `problem.rb:425-426`) that would otherwise turn a normal problem's description into a student-facing document. The API's `GET /api/v1/problems/:id/description` explicitly gates on `can_view_problem_pdf?` — for a viva problem that's `false` for students, so the endpoint returns 403 rather than the text. (The interviewer LLM does echo scenario content back into the transcript it generates — that's a *rendering of the interview*, not of the raw field, and only after the student has started the session.) | `app/controllers/api/v1/problems_controller.rb:50-58` |
| `viva_prompt` (examiner briefing + rubric) | **No, never — not even to admins via the API** | Absent from `problem_params`, `problem_admin_json`, and `problem_list_json` in the API controller; only reachable through the web admin form and the LLM system-prompt assembly | `app/controllers/api/v1/problems_controller.rb:312-318` (params), `:337-361` (admin json), `:384-402` (list json) |
| `viva_conduct` tags (shared persona layer) | **No** | Forced `public: false` at the model level for all LLM-only tag kinds (`llm_prompt`, `viva_conduct`), regardless of what an author sets | `app/models/tag.rb` (`force_private_for_llm_kinds`) |
| Grounding materials (`GroundingMaterial`) | **No — instructor-only, no student route exists at all** | `GroundingMaterialsController` is gated by `admin_authorization` (not even `group_editor_authorization`) and the resource is registered with `except: [:show]` — there is no route a student could hit even if authenticated as one | `app/controllers/grounding_materials_controller.rb:2`, `config/routes.rb:59` |

**Summary:** the only viva-related content a student ever sees is (1) the
Start/View Viva buttons and the Viva Info card, and (2) whatever the
interviewer LLM chooses to say back to them inside the chat transcript. The
scenario, the PDF, the rubric, the persona layer, and grounding material are
all authoring/grading inputs, not student-visible artifacts in their own
right.

---

## 3. Scoring

**Score = max points over every attempt for that problem, including archived
ones.** `MainController#prepare_list_information` computes two different
things from two deliberately different scopes of the same base query
(`app/controllers/main_controller.rb:180-219`):

```ruby
submissions = Submission.where(user: @current_user, problem: @problems)
submissions = submissions.where(submitted_at: @current_user.active_contests_range) if GraderConfiguration.contest_mode?

# canonical "current" submission (View/Start Viva button target) — excludes archived
last_sub_ids = submissions.where(viva_archived_at: nil).group(:problem_id).pluck('max(id)')

# max score shown on the list — does NOT exclude archived
submissions.group(:problem_id).pluck('problem_id', 'max(points)')
```

- The **canonical current submission** (what "View Viva" links to, what
  gates the Start Viva button) excludes archived sessions.
- The **max score** does **not** exclude archived sessions — it's computed
  over the same base `submissions` scope without the `viva_archived_at: nil`
  filter.

This is deliberate: **restarting can never lower your score.** A student who
archives a low-scoring attempt and retakes it keeps whichever attempt scored
higher. This is the same rule ordinary code submissions already follow
(number/max-points logic never excludes prior attempts either) — viva just
makes the mechanism more visible because archiving is a first-class action
here.

**Main-list scoping in contest mode.** Both scopes above start from the same
`submissions` local, which — when `GraderConfiguration.contest_mode?` is true
— is *already* filtered to `submitted_at` inside
`@current_user.active_contests_range` (only contests the user is currently,
actively enrolled in). So while contest mode is on, both the canonical
submission *and* the max-score aggregate on `/main/list` only consider
sessions whose `submitted_at` (= session start, see below) falls inside an
active contest window for that user — an out-of-contest attempt's score
doesn't just stop being "current," it temporarily disappears from the
max-score number shown on the list too. It reappears the moment the user is
back inside a qualifying window or contest mode is switched off; nothing
about the underlying `Submission` row changes.

**Contest reports key on `submitted_at`, which for a viva is session
*start*, not completion.** `ReportController#submission_in_range`
(`app/controllers/report_controller.rb:628-638`) buckets submissions by
`submitted_at` (or by id range) with no viva-specific carve-out; it's the
same helper used by every report action (`submission`, `submission_query`,
score summaries, etc. — `report_controller.rb:38,63,67,145,180,221`). Because
`VivaSessionsController#start` sets `submitted_at: Time.zone.now` when the
`Submission` is created (`viva_sessions_controller.rb:89-98`) — before any
turns are exchanged and long before grading finishes — a report window that
captures the moment a student *began* a viva will include that attempt even
if grading completes well after the window nominally closed.

**Closing-bell caveat.** Grading is asynchronous and can legitimately land
minutes after a contest's stop time even under today's (Phase A) behavior —
the interviewer may still be mid-conversation at the bell, and the grader LLM
call itself takes time once the interview ends. (Phase B — not yet built —
adds a hard window-end cutoff that force-finishes an in-window session's
interview, but even then the *grading* pass still runs after the cutoff and
takes real wall-clock time.) **Operational rule: don't pull final contest
score tables the instant a contest window closes — wait until the graders
page (`/grader_processes/queues`) shows no in-flight viva jobs.**

---

## 4. Start-eligibility

`VivaSessionsController#start` (`app/controllers/viva_sessions_controller.rb:33-106`)
gates every attempt on `problems.viva_daily_limit` (nullable integer,
`problem.rb`), resolved by `daily_start_limit_for`
(`viva_sessions_controller.rb:280-295`):

| `viva_daily_limit` | Meaning | Enforcement |
|---|---|---|
| `nil` | Fall back to the site-wide `GraderConfiguration['viva.practice_daily_start_limit']` (seeded default **3**, `db/seeds.rb:211-216`). If that config key is itself missing/blank/non-positive, fall back further to a hardcoded `DAILY_START_LIMIT_FALLBACK = 3` — a misconfigured global key must fail safe to a limit, never to "unlimited." | Counts every `Submission` for that user+problem started today (`submitted_at >= beginning_of_day`), **including archived ones** — restarting does not refund the day's budget. |
| `N > 0` | At most N starts per student per problem per calendar day. | Same counting rule as above. |
| `0` | **Contest-only.** The problem can never be started outside an active contest window. | `VivaSessionsController#start` checks `GraderConfiguration.contest_mode?` directly; the earlier `can_submit_to_problem?` gate has already proven (for a student, via its `:submit` arm) the problem is visible right now only because it's part of an active, enrolled contest, so the contest-mode flag alone is sufficient today (no per-contest budget exists yet — that's the Phase B work in the context-policy spec). Editors reaching the gate via its `:edit` arm are still blocked here in normal mode; admins skip the guard entirely. |

**Admins are exempt from the whole guard block** — both the daily-limit
count and the `0`/contest-only branch are inside `unless @current_user.admin?`
(`viva_sessions_controller.rb:67-90`). In practice this means a problem
author (who is typically an admin) can start/restart their own viva as often
as needed to test-drive a briefing, with no daily-limit or contest-only
friction. **This is not the same as the planned, dedicated "test session"
flow** (design item D7 in `docs/superpowers/specs/2026-07-20-viva-deployment-readiness-design.md`,
not yet implemented) — today's admin-exempt sessions are ordinary
`Submission` rows and still count toward reports and stats exactly like any
other viva attempt; only the start-time guard is bypassed.

The resolved limit and remaining count are surfaced on the Viva Info card:
"N of L starts left today," "Contest-only viva — starts are governed by the
contest" (limit `0`), or "Unlimited starts (admin)."
