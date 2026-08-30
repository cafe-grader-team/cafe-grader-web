require "test_helper"

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
    assert_redirected_to login_main_path
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

  # --- retake-policy visibility ---

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
end
