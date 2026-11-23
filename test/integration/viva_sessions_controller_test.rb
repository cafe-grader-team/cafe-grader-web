require "test_helper"
require "minitest/mock"   # Object#stub, for the #refresh test below

class VivaSessionsControllerTest < ActionDispatch::IntegrationTest
  # `viva_sessions#start` requires both:
  #   - a problem with mode=:viva_exam
  #   - a Language with name='viva' (seeded; not in fixtures)
  # We test the failure paths plus the basic auth boundary.

  setup do
    @owner_sub = submissions(:add1_by_john)         # owned by `john`
    @other_sub = submissions(:add1_by_admin)        # owned by admin (john not the owner)
  end

  # --- Authorization on show ---

  test "unauthenticated cannot view viva session" do
    get viva_submission_path(@owner_sub)
    assert_redirected_to_login
  end

  test "owner can view their viva session" do
    sign_in_as("john", "hello")
    get viva_submission_path(@owner_sub)
    assert_response :success
  end

  test "admin can view any viva session" do
    sign_in_as("admin", "admin")
    get viva_submission_path(@other_sub)
    assert_response :success
  end

  # --- Transcript rendering ---
  #
  # Students type C++ in the answer box. Both render paths used to hand the
  # text to an HTML sanitizer/filter, which read `vector<int>` as a tag and
  # dropped it — the student saw `vector v;` in their own history and
  # panicked (the stored turn was fine). Every role must render `<` literally.

  test "transcript renders template brackets literally in every role" do
    @owner_sub.viva_turns.create!(role: :student,   status: :ok, content: "I used vector<int> v; and map<string, vector<int>> idx;")
    @owner_sub.viva_turns.create!(role: :assistant, status: :ok, content: "Why vector<pair<int,int>> and not `set<int>`? Note a < b.")
    @owner_sub.viva_turns.create!(role: :assistant, status: :error, content: "Net::ReadTimeout #<Net::ReadTimeout>")
    @owner_sub.viva_turns.create!(role: :system,    status: :ok, content: "(cap<hard> reached)")
    sign_in_as("john", "hello")
    get viva_submission_path(@owner_sub)
    assert_response :success
    assert_includes response.body, "vector&lt;int&gt; v; and map&lt;string, vector&lt;int&gt;&gt; idx;"
    assert_includes response.body, "Why vector&lt;pair&lt;int,int&gt;&gt; and not <code class=\"prettyprint\">set&lt;int&gt;</code>? Note a &lt; b."
    assert_includes response.body, "Net::ReadTimeout #&lt;Net::ReadTimeout&gt;"
    assert_includes response.body, "(cap&lt;hard&gt; reached)"
  end

  test "transcript never executes HTML typed into a turn" do
    @owner_sub.viva_turns.create!(role: :student,   status: :ok, content: "<img src=x onerror=alert(1)><script>alert(2)</script>")
    @owner_sub.viva_turns.create!(role: :assistant, status: :ok, content: "<img src=x onerror=alert(3)><script>alert(4)</script>")
    sign_in_as("john", "hello")
    get viva_submission_path(@owner_sub)
    assert_response :success
    assert_select "#viva-session img", count: 0
    assert_select "#viva-session script", count: 0
    assert_includes response.body, "&lt;img src=x onerror=alert(1)&gt;&lt;script&gt;alert(2)&lt;/script&gt;"
    assert_includes response.body, "&lt;img src=x onerror=alert(3)&gt;&lt;script&gt;alert(4)&lt;/script&gt;"
  end

  # The grade card's Feedback is model-written and quotes the student's C++
  # in code spans. It went through plain simple_format, whose sanitizer read
  # `map<int, set<int>>` as tags and showed `map>` (113 of 843 local grades).
  test "grade feedback renders template brackets literally and never executes HTML" do
    @owner_sub.update_columns(status: Submission.statuses[:done])
    @owner_sub.viva_grades.create!(total_points: 70,
      narrative: "You chose `map<int, set<int>>` well, but vector<Item> needs a < check. <img src=x onerror=alert(5)>")
    sign_in_as("john", "hello")
    get viva_submission_path(@owner_sub)
    assert_response :success
    assert_includes response.body, "<code class=\"prettyprint\">map&lt;int, set&lt;int&gt;&gt;</code>"
    assert_includes response.body, "vector&lt;Item&gt; needs a &lt; check. &lt;img src=x onerror=alert(5)&gt;"
    assert_select "#viva-session img", count: 0
  end

  # --- Authorization on show / refresh (view-authorization gate) ---
  #
  # Before this gate existed, #show/#refresh had no authorization beyond
  # check_valid_login — any logged-in student could read any other
  # student's viva transcript/grade by guessing sequential submission ids.
  # These lock in the fix via the platform's existing
  # User#can_view_submission? predicate.

  test "non-owner student cannot view another user's viva session when view_submission is false" do
    sign_in_as("james", "morning")
    @owner_sub.problem.update!(view_submission: false)
    get viva_submission_path(@owner_sub)
    assert_redirected_to list_main_path
    assert_match(/not allowed to view this viva session/i, flash[:alert])
  end

  test "non-owner student cannot refresh another user's viva session when view_submission is false" do
    sign_in_as("james", "morning")
    @owner_sub.problem.update!(view_submission: false)
    get viva_refresh_submission_path(@owner_sub)
    assert_redirected_to list_main_path
    assert_match(/not allowed to view this viva session/i, flash[:alert])
  end

  test "admin can still view a viva session owned by another user when view_submission is false" do
    sign_in_as("admin", "admin")
    @owner_sub.problem.update!(view_submission: false)
    get viva_submission_path(@owner_sub)
    assert_response :success
  end

  test "student owner sees system turns (jailbreak warnings, practice notices)" do
    # System turns carry content students MUST see (e.g. jailbreak-attempt
    # warnings, practice-mode notices) — they must not be admin-gated.
    sign_in_as("john", "hello")
    @owner_sub.viva_turns.create!(role: :system, status: :ok, content: "VISIBILITY-PROBE-WARNING")
    get viva_submission_path(@owner_sub)
    assert_response :success
    assert_includes @response.body, "VISIBILITY-PROBE-WARNING"
  end

  # --- answer enforces ownership ---

  test "non-owner cannot answer in another user's viva session" do
    sign_in_as("john", "hello")
    post viva_answer_submission_path(@other_sub), params: { content: "hi" }
    assert_redirected_to list_main_path
  end

  test "admin cannot answer in another user's viva session" do
    # Admins can VIEW other students' viva sessions (assert above) but must
    # not be able to POST on their behalf — that would corrupt transcript
    # ownership. Before the fix the controller allowed any admin to answer
    # in any session via `|| @current_user.admin?`; the new policy is
    # owner-only, regardless of admin role.
    sign_in_as("admin", "admin")
    assert_no_difference "VivaTurn.count" do
      post viva_answer_submission_path(@owner_sub), params: { content: "hi" }
    end
    assert_redirected_to list_main_path
  end

  test "admin can still answer in their own viva session" do
    # Regression guard: removing the admin-bypass shouldn't accidentally
    # block admin from posting to a viva session they themselves own.
    # Auth passes; the request then redirects out via the empty-content
    # validation, which is the same path the owner case takes.
    sign_in_as("admin", "admin")
    post viva_answer_submission_path(@other_sub), params: { content: "   " }
    assert_response :redirect
    refute_equal list_main_path, @response.headers["Location"],
      "should not be redirected to list (auth failure); should fall through to validation redirect"
  end

  test "owner gets validation error when answering with empty content" do
    sign_in_as("john", "hello")
    post viva_answer_submission_path(@owner_sub), params: { content: "   " }
    assert_response :redirect # redirect to viva path with alert
  end

  test "answer at hard cap force-finishes and enqueues grading" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(viva_hard_cap: 2)
    2.times { |i| @owner_sub.viva_turns.create!(role: :student, status: :ok, content: "a#{i}") }
    assert_enqueued_with(job: Llm::VivaGradeAssistJob) do
      post viva_answer_submission_path(@owner_sub), params: { content: "one more" }
    end
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_equal "evaluating", @owner_sub.reload.status
    assert_equal 2, @owner_sub.viva_turns.where(role: :student).count,
      "the over-cap answer must not be recorded"
  end

  # --- start failure paths ---

  test "start redirects when problem is not a viva exam" do
    sign_in_as("admin", "admin")
    # prob_add has mode default (general), not viva_exam
    post viva_start_problem_path(problems(:prob_add))
    assert_redirected_to list_main_path
  end

  # --- retry_turn ---

  # Helper: build a :error assistant turn so we have a target to retry.
  def make_failed_turn(submission)
    submission.viva_turns.create!(
      role:    :assistant,
      status:  :error,
      content: "boom"
    )
  end

  test "owner can retry a failed turn on their own viva" do
    sign_in_as("john", "hello")
    turn = make_failed_turn(@owner_sub)
    assert_enqueued_with(job: Llm::VivaTurnAssistJob) do
      post viva_retry_turn_submission_path(@owner_sub, turn_id: turn.id)
    end
    assert_redirected_to viva_submission_path(@owner_sub)
    turn.reload
    assert_predicate turn, :processing?, "turn should be reset to :processing"
    assert_nil turn.content, "content should be cleared so the spinner shows again"
  end

  test "admin can retry a failed turn on someone else's viva" do
    sign_in_as("admin", "admin")
    turn = make_failed_turn(@owner_sub)  # john's session, admin retries
    assert_enqueued_with(job: Llm::VivaTurnAssistJob) do
      post viva_retry_turn_submission_path(@owner_sub, turn_id: turn.id)
    end
    assert_redirected_to viva_submission_path(@owner_sub)
    turn.reload
    assert_predicate turn, :processing?
  end

  test "unrelated user cannot retry someone else's viva turn" do
    # `mary` is neither the owner (john) nor an admin.
    sign_in_as("mary", "mary")
    turn = make_failed_turn(@owner_sub)
    assert_no_enqueued_jobs(only: Llm::VivaTurnAssistJob) do
      post viva_retry_turn_submission_path(@owner_sub, turn_id: turn.id)
    end
    turn.reload
    assert_predicate turn, :error?, "turn must NOT have been reset"
  end

  test "retry refuses when turn is not in :error state" do
    sign_in_as("john", "hello")
    fresh = @owner_sub.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    assert_no_enqueued_jobs(only: Llm::VivaTurnAssistJob) do
      post viva_retry_turn_submission_path(@owner_sub, turn_id: fresh.id)
    end
    fresh.reload
    assert_predicate fresh, :processing?, "in-flight turn should not be reset"
  end

  test "retry refuses when target turn is a system or student turn" do
    sign_in_as("john", "hello")
    student_turn = @owner_sub.viva_turns.create!(role: :student, status: :ok, content: "answer")
    # Hack the status to error to bypass the status guard and isolate the role guard.
    VivaTurn.where(id: student_turn.id).update_all(status: 2) # :error
    assert_no_enqueued_jobs(only: Llm::VivaTurnAssistJob) do
      post viva_retry_turn_submission_path(@owner_sub, turn_id: student_turn.id)
    end
  end

  # --- answer below hard cap: happy path (Task 5 review follow-up) ---

  test "answer below hard cap records a student turn and enqueues the assist job" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(viva_hard_cap: 15)
    assert @owner_sub.viva_turns.where(role: :student).count < @owner_sub.problem.viva_hard_cap,
      "fixture must start below the hard cap for this to be a meaningful test"

    assert_enqueued_with(job: Llm::VivaTurnAssistJob) do
      assert_difference "@owner_sub.viva_turns.where(role: :student).count", 1 do
        post viva_answer_submission_path(@owner_sub), params: { content: "my answer" }
      end
    end
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_equal "submitted", @owner_sub.reload.status,
      "below the hard cap the interview keeps going — status must not flip to evaluating"
    placeholder = @owner_sub.viva_turns.order(:id).last
    assert_equal "assistant", placeholder.role
    assert_predicate placeholder, :processing?
  end

  # --- restart (self-service retake; every viva is practice, 2026-07-21 design) ---

  # `viva` Language isn't in fixtures (see the file-level comment above) —
  # find_or_create_by! so this works whether or not another test already
  # seeded it within this run.
  def viva_language
    Language.find_or_create_by!(name: 'viva') { |l| l.pretty_name = 'Viva Exam' }
  end

  test "owner can restart their own viva" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(compilation_type: :viva_exam)
    post viva_restart_submission_path(@owner_sub)
    assert @owner_sub.reload.viva_archived_at.present?
  end

  test "non-owner cannot restart another user's viva" do
    sign_in_as("admin", "admin")
    @owner_sub.problem.update!(compilation_type: :viva_exam)
    post viva_restart_submission_path(@owner_sub)
    assert_nil @owner_sub.reload.viva_archived_at
  end

  test "restart refuses when the submission's problem is not a viva exam" do
    # @owner_sub's problem (prob_add) defaults to compilation_type:
    # self_contained. viva_daily_limit is a permitted param on every
    # problem, so a misconfigured non-viva problem with a daily limit set
    # must still refuse to archive — restart must never be usable as a
    # grade-manipulation vector on an ordinary coding submission.
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(viva_daily_limit: 3)
    refute @owner_sub.problem.viva_exam?, "sanity: fixture problem must not be a viva exam"
    post viva_restart_submission_path(@owner_sub)
    assert_nil @owner_sub.reload.viva_archived_at
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_match(/viva exam/i, flash[:alert])
  end

  test "restart refuses when the session is already archived" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(compilation_type: :viva_exam)
    archived_at = 1.hour.ago
    @owner_sub.update!(viva_archived_at: archived_at)
    post viva_restart_submission_path(@owner_sub)
    assert_in_delta archived_at, @owner_sub.reload.viva_archived_at, 1,
      "already-archived timestamp must not be re-stamped"
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_match(/already been archived/i, flash[:alert])
  end

  test "restart refuses while an assistant turn is still processing" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(compilation_type: :viva_exam)
    @owner_sub.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    post viva_restart_submission_path(@owner_sub)
    assert_nil @owner_sub.reload.viva_archived_at,
      "must not archive while a response is still in flight"
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_match(/current response/i, flash[:alert])
  end

  # --- daily start limit (2026-07-21 context-policy design, Phase A) ---

  test "daily start limit refuses the 4th start of the day (nil viva_daily_limit falls back to global config)" do
    # Exercised through the real #start endpoint, so the fixture problem
    # must actually pass every guard ahead of the rate limit: viva_exam
    # compilation_type, submit authorization, a seeded 'viva' Language,
    # and a viva_prompt satisfying Problem::VIVA_PROMPT_REQUIRED_SECTIONS.
    # prob_add (used elsewhere in this file) is a plain problem and would
    # be refused before ever reaching the rate-limit check, so we use
    # prob_viva (already compilation_type: viva_exam, available: true).
    # Its viva_daily_limit is nil (fixture default), so the global
    # GraderConfiguration key (3/day; see grader_configurations.yml) applies.
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_prompt: "# Rubric\nBe fair.")
    assert_nil problem.viva_daily_limit, "sanity: fixture default must be nil (falls back to global config)"
    user = users(:john)
    3.times do
      s = Submission.create!(user: user, problem: problem, language: viva_language,
                             status: :submitted, submitted_at: Time.zone.now, viva_archived_at: Time.zone.now)
      s.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    end
    post viva_start_problem_path(problem)   # 4th today -> refused
    assert_redirected_to list_main_path
    assert_match(/Daily practice limit/, flash[:alert])
    assert_equal 3, problem.submissions.where(user: user).count
  end

  test "start rate limit honors the GraderConfiguration override when viva_daily_limit is nil" do
    # Same setup as above, but with viva.practice_daily_start_limit lowered
    # to 1 via config — proves the controller reads the runtime setting
    # rather than a hardcoded constant.
    set_grader_config("viva.practice_daily_start_limit", 1)
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_prompt: "# Rubric\nBe fair.")
    user = users(:john)
    Submission.create!(user: user, problem: problem, language: viva_language,
                       status: :submitted, submitted_at: Time.zone.now, viva_archived_at: Time.zone.now)
              .viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    post viva_start_problem_path(problem)   # 2nd today -> refused under the lowered limit
    assert_redirected_to list_main_path
    assert_match(/Daily practice limit reached.*\(1\/day\)/, flash[:alert])
    assert_equal 1, problem.submissions.where(user: user).count
  end

  test "per-problem viva_daily_limit of 1 refuses the 2nd start of the day, overriding the global config" do
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 1, viva_prompt: "# Rubric\nBe fair.")
    user = users(:john)
    Submission.create!(user: user, problem: problem, language: viva_language,
                       status: :submitted, submitted_at: Time.zone.now, viva_archived_at: Time.zone.now)
              .viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    post viva_start_problem_path(problem)   # 2nd today -> refused under the per-problem limit
    assert_redirected_to list_main_path
    assert_match(/Daily practice limit reached.*\(1\/day\)/, flash[:alert])
    assert_equal 1, problem.submissions.where(user: user).count
  end

  test "viva_daily_limit of 0 refuses starts outside a contest" do
    viva_language # seed the 'viva' Language so the earlier guard doesn't shadow this one
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 0, viva_prompt: "# Rubric\nBe fair.")
    assert_no_difference "Submission.count" do
      post viva_start_problem_path(problem)
    end
    assert_redirected_to list_main_path
    assert_match(/can only be taken during a contest/i, flash[:alert])
  end

  test "viva_daily_limit of 0 allows a start inside an active contest (contest_mode? on)" do
    # In contest mode, @current_user.problems_for_action(:submit) (checked
    # earlier in #start) already proves the problem is visible only because
    # it's included in an active contest the student is enrolled in right
    # now — see the comment on the guard in VivaSessionsController#start.
    viva_language # seed the 'viva' Language
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 0, viva_prompt: "# Rubric\nBe fair.")
    contest = contests(:contest_a)
    ContestProblem.create!(contest: contest, problem: problem, number: 99, enabled: true)
    ContestUser.create!(contest: contest, user: users(:john), role: 0, enabled: true,
                         start_offset_second: 0, extra_time_second: 0)
    set_grader_config("system.mode", "contest")

    assert_enqueued_with(job: Llm::VivaTurnAssistJob) do
      post viva_start_problem_path(problem)
    end
    assert_redirected_to viva_submission_path(Submission.last)
  end

  test "viva_daily_limit of 0 allows one counted session in contest mode, then refuses with the proctor message" do
    viva_language
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 0, viva_prompt: "# Rubric\nBe fair.")
    contest = contests(:contest_a)
    ContestProblem.create!(contest: contest, problem: problem, number: 99, enabled: true)
    ContestUser.create!(contest: contest, user: users(:john), role: 0, enabled: true,
                         start_offset_second: 0, extra_time_second: 0)
    set_grader_config("system.mode", "contest")

    post viva_start_problem_path(problem)
    first = Submission.last
    assert_redirected_to viva_submission_path(first)
    first.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    first.update!(viva_archived_at: Time.zone.now)   # as if restarted

    assert_no_difference "Submission.count" do
      post viva_start_problem_path(problem)
    end
    assert_redirected_to list_main_path
    assert_match(/You have used your attempt.*ask a proctor/, flash[:alert])
  end

  # --- the exam path itself: contest mode, limit 0 (design 2026-10-07, A1/A3) ---

  # prob_viva as a contest-only viva in contest_a (running now), john enrolled
  # as a student, contest mode on. Returns the problem.
  def setup_contest_only_viva
    viva_language
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 0, viva_prompt: "# Rubric\nBe fair.")
    ContestProblem.create!(contest: contests(:contest_a), problem: problem, number: 99, enabled: true)
    ContestUser.create!(contest: contests(:contest_a), user: users(:john), role: 0, enabled: true,
                        start_offset_second: 0, extra_time_second: 0)
    set_grader_config("system.mode", "contest")
    problem
  end

  def contest_session_for_john(problem, answered:)
    Submission.create!(user: users(:john), problem: problem, language: viva_language,
                       status: :submitted, submitted_at: Time.zone.now).tap do |sub|
      sub.viva_turns.create!(role: :assistant, status: :ok, content: 'Q?')
      sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once') if answered
    end
  end

  test "contest mode, limit 0: the session page counts the one attempt and offers no End button" do
    sign_in_as("john", "hello")
    problem = setup_contest_only_viva
    sub = contest_session_for_john(problem, answered: false)

    get viva_submission_path(sub)
    assert_response :success
    assert_match(/Contest-only viva — 1 of 1 attempt left today/, @response.body)

    sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    get viva_submission_path(sub)
    assert_match(/Contest-only viva — 0 of 1 attempt left today/, @response.body)
    assert_select "form[action=?]", viva_finish_submission_path(sub), 0
  end

  test "contest mode, limit 0: Restart is refused on an answered session" do
    sign_in_as("john", "hello")
    problem = setup_contest_only_viva
    sub = contest_session_for_john(problem, answered: true)

    get viva_submission_path(sub)
    assert_select "form[action=?]", viva_restart_submission_path(sub), 0

    post viva_restart_submission_path(sub)
    assert_nil sub.reload.viva_archived_at
    assert_redirected_to viva_submission_path(sub)
    assert_match(/Restart is not available.*You have used your attempt/, flash[:alert])
  end

  test "contest mode, limit 0: Restart is allowed on a session with no answer" do
    sign_in_as("john", "hello")
    problem = setup_contest_only_viva
    sub = contest_session_for_john(problem, answered: false)

    get viva_submission_path(sub)
    assert_select "form[action=?]", viva_restart_submission_path(sub), 1

    post viva_restart_submission_path(sub)
    assert sub.reload.viva_archived_at.present?
    assert_redirected_to list_main_path
    assert_match(/only available during a contest/, flash[:notice])
  end

  test "restart is hidden and refused when the student could not start again" do
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 1, viva_prompt: "# Rubric\nBe fair.")
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :submitted, submitted_at: Time.zone.now)
    sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once')

    get viva_submission_path(sub)
    assert_response :success
    assert_no_match(/Restart viva/, @response.body)
    assert_select "form[action=?]", viva_restart_submission_path(sub), 0

    post viva_restart_submission_path(sub)   # e.g. from a stale tab
    assert_nil sub.reload.viva_archived_at
    assert_redirected_to viva_submission_path(sub)
    assert_match(/Restart is not available/, flash[:alert])
  end

  test "restart stays available on a session with no answer under limit 1" do
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 1, viva_prompt: "# Rubric\nBe fair.")
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :submitted, submitted_at: Time.zone.now)

    get viva_submission_path(sub)
    assert_select "form[action=?] button", viva_restart_submission_path(sub), text: 'Restart viva'
    assert_no_match(/Restart practice viva/, @response.body, 'it shows during exams too: no "practice" in the label')
    post viva_restart_submission_path(sub)
    assert sub.reload.viva_archived_at.present?
  end

  test "a staff grant shows on the session page and frees a start" do
    viva_language
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 1, viva_prompt: "# Rubric\nBe fair.")
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :done, submitted_at: Time.zone.now)
    sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    sub.grant_viva_retake!(by: users(:admin))

    get viva_submission_path(sub)
    assert_match(/Another attempt allowed by admin/, @response.body)
    assert_match(/does not count toward the start limit/, @response.body)

    assert_difference "Submission.count", 1 do
      post viva_start_problem_path(problem)
    end
    assert_redirected_to viva_submission_path(Submission.last)
  end

  # --- a closed (archived) session takes no answers and no retries (design 2026-10-07, A4) ---
  #
  # Final review of the retake work: on a session closed by "Allow another
  # attempt" the owner still saw the answer form, a POST to viva/turns was
  # accepted, and a second live session could then be started beside it.

  test "a granted open session hides the answer form and refuses answers and retries, also after a new start" do
    viva_language
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_daily_limit: 1, viva_prompt: "# Rubric\nBe fair.")
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :submitted, submitted_at: Time.zone.now)
    sub.viva_turns.create!(role: :assistant, status: :ok, content: 'Q?')
    sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    failed = make_failed_turn(sub)
    assert_equal :granted, sub.grant_viva_retake!(by: users(:admin))

    get viva_submission_path(sub)
    assert_response :success
    assert_select "form[action=?]", viva_answer_submission_path(sub), 0
    assert_select "form[action=?]", viva_retry_turn_submission_path(sub, turn_id: failed.id), 0
    assert_match(/This session was closed without a grade\./, @response.body)
    assert_no_match(/its score still counts toward the best/, @response.body)

    assert_no_enqueued_jobs do
      assert_no_difference -> { sub.viva_turns.where(role: :student).count } do
        post viva_answer_submission_path(sub), params: {content: 'a second answer'}
      end
    end
    assert_redirected_to viva_submission_path(sub)
    assert_match(/This session has been closed/, flash[:alert])

    assert_no_enqueued_jobs do
      post viva_retry_turn_submission_path(sub, turn_id: failed.id)
    end
    assert_redirected_to viva_submission_path(sub)
    assert_match(/This session has been closed/, flash[:alert])
    assert_predicate failed.reload, :error?, 'the failed turn must not be reset'

    # The grant frees one start; the new session is the only live one.
    assert_difference "Submission.count", 1 do
      post viva_start_problem_path(problem)
    end
    fresh = Submission.last
    assert_redirected_to viva_submission_path(fresh)
    assert_no_difference -> { sub.viva_turns.where(role: :student).count } do
      post viva_answer_submission_path(sub), params: {content: 'answer on the closed session'}
    end
    assert_match(/This session has been closed/, flash[:alert])
    assert_equal 'submitted', sub.reload.status
  end

  test "a closed session with a grade says its score still counts toward the best" do
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :done, points: 80, submitted_at: Time.zone.now)
    sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    sub.grant_viva_retake!(by: users(:admin))
    get viva_submission_path(sub)
    assert_match(/This session is closed; its score still counts toward the best\./, @response.body)
    assert_match(/A fresh session can be started from the problem list when a start is left\./, @response.body)
  end

  test "start with a session still open names the problem list and staff, not an admin archive" do
    viva_language
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_prompt: "# Rubric\nBe fair.")
    Submission.create!(user: users(:john), problem: problem, language: viva_language,
                       status: :submitted, submitted_at: Time.zone.now)
    assert_no_difference "Submission.count" do
      post viva_start_problem_path(problem)
    end
    assert_redirected_to list_main_path
    assert_match(/Open it from the problem list, or ask staff to allow another attempt\./, flash[:alert])
  end

  test "an admin cannot retry a turn on a closed session either" do
    sign_in_as("admin", "admin")
    @owner_sub.update!(viva_archived_at: Time.zone.now)   # e.g. the student pressed Restart
    turn = make_failed_turn(@owner_sub)
    assert_no_enqueued_jobs(only: Llm::VivaTurnAssistJob) do
      post viva_retry_turn_submission_path(@owner_sub, turn_id: turn.id)
    end
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_match(/This session has been closed/, flash[:alert])
    assert_predicate turn.reload, :error?
  end

  # --- retake-policy visibility ---

  test "refresh renders the transcript without building the start policy (only show reads it)" do
    sign_in_as("john", "hello")
    Viva::StartPolicy.stub(:new, ->(*) { flunk 'the 3 s refresh must not build Viva::StartPolicy' }) do
      get viva_refresh_submission_path(@owner_sub)
    end
    assert_response :success
    assert_select "#viva-session", 1
  end

  test "show displays the starts-left line for every viva" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(compilation_type: :viva_exam)
    # The fixture's submitted_at is 2019 (outside "today"'s count) — restamp
    # it so it counts as one of today's starts, exercising the real
    # used/left arithmetic (fixture default limit is 3/day; see
    # grader_configurations.yml).
    @owner_sub.update!(submitted_at: Time.zone.now)
    # Zero student turns yet: an unengaged session is free (doesn't count).
    get viva_submission_path(@owner_sub)
    assert_response :success
    assert_match(/3 of 3 starts left today/, @response.body)
    # Once the student has answered, this session consumes one slot.
    @owner_sub.viva_turns.create!(role: :student, status: :ok, content: 'answered once')
    get viva_submission_path(@owner_sub)
    assert_match(/2 of 3 starts left today/, @response.body)
  end

  test "show tells an admin viewing their own viva they're unlimited, not a countdown" do
    # Admins are exempt from the daily-start limiter in #start (see the
    # `unless @current_user.admin?` guard there) — the card must not show
    # them a countdown that doesn't actually apply to them.
    sign_in_as("admin", "admin")
    @other_sub.problem.update!(compilation_type: :viva_exam)
    get viva_submission_path(@other_sub)
    assert_response :success
    assert_match(/Unlimited starts \(admin\)/, @response.body)
    assert_no_match(/starts left today/, @response.body)
    assert_no_match(/\|\s*Unlimited starts/, @response.body, "no stray HAML pipe before the text")
  end

  test "show tells the owner of a contest-only viva it can be taken only during a contest" do
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_prompt: "# Rubric\nBe fair.", viva_daily_limit: 0)
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :submitted, submitted_at: Time.zone.now)
    get viva_submission_path(sub)
    assert_response :success
    assert_match(/Contest-only viva — can be taken only during a contest/, @response.body)
    assert_no_match(/starts left today/, @response.body)
    assert_no_match(/\|\s*Contest-only viva/, @response.body, "no stray HAML pipe before the text")
  end

  test "zero-engagement sessions do not count toward the daily start limit" do
    set_grader_config("viva.practice_daily_start_limit", 1)
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_prompt: "# Rubric\nBe fair.")
    user = users(:john)
    # An archived greeting-only session (opened, never answered) is free.
    Submission.create!(user: user, problem: problem, language: viva_language,
                       status: :submitted, submitted_at: Time.zone.now, viva_archived_at: Time.zone.now)
    post viva_start_problem_path(problem)
    assert_equal 2, problem.submissions.where(user: user).count,
                 "a zero-turn session must not consume the daily budget"
  end

  test "finish refuses with no student turns, then ends the viva and enqueues grading" do
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_prompt: "# Rubric\nBe fair.")
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :submitted, submitted_at: Time.zone.now)

    post viva_finish_submission_path(sub)
    assert_redirected_to viva_submission_path(sub)
    assert_match(/Answer at least one question/, flash[:alert])
    assert_equal 'submitted', sub.reload.status

    sub.viva_turns.create!(role: :student, status: :ok, content: 'my answer')
    assert_enqueued_with(job: Llm::VivaGradeAssistJob) do
      post viva_finish_submission_path(sub)
    end
    assert_redirected_to viva_submission_path(sub)
    assert_equal 'evaluating', sub.reload.status
    assert sub.viva_turns.where(role: :system).where("content LIKE '%student ended%'").exists?,
           "finish must leave the end-of-interview system turn"
  end

  # --- concurrent POSTs on one session (backlog: viva double-enqueue race) ---
  #
  # #answer and #finish take a row lock on the submission and re-read its
  # state before acting. The hook below fires once, inside that lock, and
  # plays the part of the concurrent request that committed first — a
  # double-click on Send, a second tab, a browser retry. Without the lock
  # both requests read the same pre-cap turn count and both queued a grade
  # job for one interview. The hook is a no-op (nil) for every other test.

  module SubmissionLockHook
    mattr_accessor :once # one-shot proc, consumed on the first lock! call

    def lock!(...)
      if (hook = SubmissionLockHook.once)
        SubmissionLockHook.once = nil
        hook.call(self)
      end
      super
    end
  end
  Submission.prepend(SubmissionLockHook)

  teardown do
    SubmissionLockHook.once = nil
  end

  test "answer at hard cap does not queue a second grade job when a concurrent request finished first" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(viva_hard_cap: 2)
    2.times { |i| @owner_sub.viva_turns.create!(role: :student, status: :ok, content: "a#{i}") }
    # The other request force-finished and committed while this one waited for the lock.
    SubmissionLockHook.once = ->(sub) { Submission.find(sub.id).update_columns(status: :evaluating) }

    assert_no_enqueued_jobs(only: Llm::VivaGradeAssistJob) do
      assert_no_difference "VivaTurn.count" do
        post viva_answer_submission_path(@owner_sub), params: { content: "one more" }
      end
    end
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_match(/grading in progress/i, flash[:alert])
    assert_nil SubmissionLockHook.once, "answer must take the row lock (the hook never ran)"
  end

  test "answer does not double-post when a concurrent answer landed first" do
    sign_in_as("john", "hello")
    @owner_sub.problem.update!(viva_hard_cap: 15)
    # The other request recorded its answer and placeholder while this one waited for the lock.
    SubmissionLockHook.once = ->(sub) do
      sub.viva_turns.create!(role: :student,   status: :ok,         content: "the first click")
      sub.viva_turns.create!(role: :assistant, status: :processing, content: nil)
    end

    assert_no_enqueued_jobs(only: Llm::VivaTurnAssistJob) do
      post viva_answer_submission_path(@owner_sub), params: { content: "the second click" }
    end
    assert_redirected_to viva_submission_path(@owner_sub)
    assert_match(/waiting for the previous response/i, flash[:alert])
    assert_equal 0, @owner_sub.viva_turns.where(content: "the second click").count,
      "the second click must not be recorded as another student turn"
    assert_nil SubmissionLockHook.once, "answer must take the row lock (the hook never ran)"
  end

  test "finish does not queue a second grade job when a concurrent request ended the interview first" do
    sign_in_as("john", "hello")
    problem = problems(:prob_viva)
    problem.update!(viva_prompt: "# Rubric\nBe fair.")
    sub = Submission.create!(user: users(:john), problem: problem, language: viva_language,
                             status: :submitted, submitted_at: Time.zone.now)
    sub.viva_turns.create!(role: :student, status: :ok, content: "my answer")
    SubmissionLockHook.once = ->(s) { Submission.find(s.id).update_columns(status: :evaluating) }

    assert_no_enqueued_jobs(only: Llm::VivaGradeAssistJob) do
      assert_no_difference "VivaTurn.count" do
        post viva_finish_submission_path(sub)
      end
    end
    assert_redirected_to viva_submission_path(sub)
    assert_match(/already ended/i, flash[:alert])
    assert_nil SubmissionLockHook.once, "finish must take the row lock (the hook never ran)"
  end

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

  test "show marks a test-drive with the badge and the unlimited-restarts line" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    drive = make_test_drive(user: users(:mary), problem: problem)
    get viva_submission_path(drive)
    assert_response :success
    assert_match(/>test-drive</, response.body, "badge")
    assert_match(/unlimited restarts/, response.body)
    assert_no_match(/\|\s*Test-drive/, response.body, "no stray HAML pipe before the text")
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

  test "an editor can test-drive a hidden (draft) viva and open the session" do
    problem = setup_test_drive_problem
    problem.update!(available: false)   # draft: students cannot see or submit it
    sign_in_as("mary", "mary")
    assert_difference -> { Submission.test_drives.count }, 1 do
      post viva_test_drive_problem_path(problem)
    end
    follow_redirect!
    assert_response :success
    assert_match(/>test-drive</, response.body, "the author lands on their own session although the problem is unavailable")
  end

  test "an admin can test-drive a viva that is in no group" do
    viva_language
    problem = problems(:prob_viva)          # fixtures keep it out of every group
    problem.update!(viva_prompt: "# Rubric\nBe fair.")
    sign_in_as("admin", "admin")
    assert_difference -> { Submission.test_drives.count }, 1 do
      post viva_test_drive_problem_path(problem)
    end
    follow_redirect!
    assert_response :success
    assert_match(/>test-drive</, response.body)
  end

  test "a finished test-drive does not block a fresh one" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    done = make_test_drive(user: users(:mary), problem: problem)
    done.update_columns(status: Submission.statuses[:done], points: 70)
    assert_difference -> { Submission.test_drives.count }, 1 do
      post viva_test_drive_problem_path(problem)
    end
    assert_not_equal done.id, Submission.test_drives.order(:id).last.id
  end

  test "restart on a test-drive refuses a fresh session when the setup is now incomplete" do
    problem = setup_test_drive_problem
    sign_in_as("mary", "mary")
    drive = make_test_drive(user: users(:mary), problem: problem)
    problem.update_columns(viva_prompt: nil)   # briefing blanked after the first start
    assert_no_difference -> { Submission.test_drives.count } do
      post viva_restart_submission_path(drive)
    end
    assert_redirected_to edit_problem_path(problem)
    assert_match(/setup is incomplete/, flash[:alert])
    assert drive.reload.viva_archived_at.present?, "the old test-drive is still archived"
  end

  # --- grade history table (spec 2026-09-23-viva-grade-history-design) ---

  # Four runs on john's session: replaced → current (by admin) → lower (batch) → error.
  def seed_grade_history(sub)
    sub.update!(status: :done, points: 70)
    old = sub.viva_grades.create!(total_points: 40, graded_at: 2.hours.ago, llm_model: 'old-model',
                                  superseded_at: 1.hour.ago, superseded_reason: 'replaced')
    cur = sub.viva_grades.create!(total_points: 70, graded_at: 1.hour.ago, llm_model: 'new-model',
                                  requested_by_id: users(:admin).id, rubric_version: 'a' * 64)
    sub.viva_grades.create!(total_points: 30, graded_at: 30.minutes.ago, llm_model: 'new-model',
                            superseded_at: 30.minutes.ago, superseded_reason: 'lower', batch_id: 'regrade-1-x')
    bad = sub.viva_grades.create!(graded_at: 10.minutes.ago, llm_model: 'new-model', superseded_at: 10.minutes.ago,
                                  superseded_reason: 'error', error: 'grader JSON failed schema check: rubric missing',
                                  llm_response_raw: '{"choices":[]}')
    old.update!(superseded_by_id: cur.id)
    [old, cur, bad]
  end

  test "an admin sees the grade history with one row per run, the badges and Make current on valid earlier runs" do
    old, cur, bad = seed_grade_history(@owner_sub)
    sign_in_as("admin", "admin")
    get viva_submission_path(@owner_sub)
    assert_response :success
    assert_select 'h6', text: 'Grade history'
    assert_select 'table.grade-history tbody tr:not(.collapse)', count: 4
    assert_select 'table.grade-history span.badge', text: 'current', count: 1
    assert_select 'table.grade-history span.badge', text: 'replaced', count: 1
    assert_select 'table.grade-history span.badge', text: 'lower', count: 1
    assert_select 'table.grade-history span.badge', text: 'error', count: 1
    assert_select 'table.grade-history .rubric', text: 'aaaaaaaa'
    assert_select 'table.grade-history .requester', text: 'admin'
    assert_select 'table.grade-history .requester', text: 'batch regrade-1-x'
    assert_select 'table.grade-history .requester', text: 'auto', minimum: 1
    assert_select "form[action=?]", adopt_viva_grade_submission_path(@owner_sub, grade_id: old.id), count: 1
    assert_select "form[action=?]", adopt_viva_grade_submission_path(@owner_sub, grade_id: cur.id), count: 0
    assert_select "form[action=?]", adopt_viva_grade_submission_path(@owner_sub, grade_id: bad.id), count: 0
    assert_includes response.body, 'rubric missing'
    assert_select 'input[name=never_lower][type=checkbox][checked]', count: 1
  end

  test "the student sees neither the grade history nor the re-run form" do
    seed_grade_history(@owner_sub)
    sign_in_as("john", "hello")
    get viva_submission_path(@owner_sub)
    assert_response :success
    assert_select 'h6', text: 'Grade history', count: 0
    assert_select 'input[name=never_lower]', count: 0
    assert_select 'table.grade-history', count: 0
  end
end
