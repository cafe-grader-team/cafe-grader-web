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
    # show has no explicit owner check — the view just renders viva_turns.
    # That's questionable, but it's the current behavior; we document it.
    assert_response :success
  end

  test "admin can view any viva session" do
    sign_in_as("admin", "admin")
    get viva_submission_path(@other_sub)
    assert_response :success
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
end
