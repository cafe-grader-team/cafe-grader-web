require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  # CommentsController has two surfaces:
  #   1. Problem hints   (nested under /problems/:problem_id/hint/...)
  #   2. Submission comments (nested under /submissions/:submission_id/comments/...)
  # Authorization layers: can_view_problem, can_edit_problem, can_view_submission,
  # can_request_llm.

  setup do
    @prob = problems(:prob_add)
    @hint = comments(:hint_for_add)
    @sub  = submissions(:add1_by_john)
  end

  # ------------------------------------------------------------
  # Problem-hint surface
  # ------------------------------------------------------------

  test "unauthenticated cannot edit a hint" do
    get edit_problem_hint_index_path(problem_id: @prob.id, id: @hint.id)
    assert_redirected_to login_main_path
  end

  test "normal user (non-editor) cannot edit a hint" do
    sign_in_as("john", "hello")
    get edit_problem_hint_index_path(problem_id: @prob.id, id: @hint.id)
    assert_response :redirect
  end

  test "admin can edit a hint" do
    sign_in_as("admin", "admin")
    get edit_problem_hint_index_path(problem_id: @prob.id, id: @hint.id), as: :turbo_stream
    assert_response :success
  end

  test "admin can update a hint" do
    sign_in_as("admin", "admin")
    patch problem_hint_path(problem_id: @prob.id, id: @hint.id),
          params: { comment: { title: "Updated", body: "new body", cost: 2.0, kind: "hint" } },
          as: :turbo_stream
    assert_response :success
    assert_equal "Updated", @hint.reload.title
  end

  # ------------------------------------------------------------
  # Submission-comment surface — LLM assist authorization
  # ------------------------------------------------------------

  test "llm_assist denied when system.llm_assist=false" do
    set_grader_config("system.llm_assist", "false")
    sign_in_as("admin", "admin")
    assert_no_difference "Comment.count" do
      post llm_assist_submission_comments_path(submission_id: @sub.id, model: 0),
           as: :turbo_stream
    end
  end

  test "llm_assist denied when problem has no llm_prompt tag" do
    set_grader_config("system.llm_assist", "true")
    set_grader_config("system.mode", "standard")
    # Ensure prob_add has no llm_prompt-kind tag in fixtures; assert nothing was created.
    sign_in_as("admin", "admin")
    assert_no_difference "Comment.count" do
      post llm_assist_submission_comments_path(submission_id: @sub.id, model: 0),
           as: :turbo_stream
    end
  end

  test "create_for_submission denied for normal user (not problem editor)" do
    sign_in_as("john", "hello")
    assert_no_difference "Comment.count" do
      post submission_comments_path(submission_id: @sub.id),
           params: { comment_title: "x", comment_body: "y" },
           as: :turbo_stream
    end
  end
end
