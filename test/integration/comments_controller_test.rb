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
    assert_redirected_to_login
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

  # ------------------------------------------------------------
  # LLM assist — ownership, model addressing, rendered body
  # ------------------------------------------------------------

  # The picker POSTs the model by NAME (a key of Rails.configuration.llm[:provider]);
  # the provider map is empty in the test env, so each test installs its own.
  def enable_llm_assist!(provider = { "stub-model" => "Llm::SelfHostAssist" })
    set_grader_config("system.llm_assist", "true")
    set_grader_config("system.mode", "standard")
    @prob.tags << Tag.create!(name: "codey-test", kind: :llm_prompt, params: "You are a tutor.")
    @saved_provider = Rails.configuration.llm[:provider]
    Rails.configuration.llm[:provider] = provider
  end

  teardown do
    Rails.configuration.llm[:provider] = @saved_provider if instance_variable_defined?(:@saved_provider)
  end

  test "llm_assist is refused when the requester does not own the submission" do
    enable_llm_assist!
    james_sub = submissions(:add1_by_james)
    sign_in_as("john", "hello")
    assert_no_difference "Comment.count" do
      assert_no_enqueued_jobs do
        post llm_assist_submission_comments_path(submission_id: james_sub.id),
             params: { model: "stub-model" }, as: :turbo_stream
      end
    end
    assert_response :forbidden
    assert_match(/LLM Assist Error/, response.body)
  end

  test "llm_assist by the owner creates the placeholder and enqueues the job for the named model" do
    enable_llm_assist!
    sign_in_as("john", "hello")
    assert_difference "Comment.count", 1 do
      assert_enqueued_with(job: Llm::SelfHostAssistJob) do
        post llm_assist_submission_comments_path(submission_id: @sub.id),
             params: { model: "stub-model" }, as: :turbo_stream
      end
    end
    assert_response :success
    comment = Comment.order(:id).last
    assert_equal "llm_assist", comment.kind
    assert_equal "stub-model", comment.llm_model
    assert_equal users(:john), comment.user
    assert_equal @sub, comment.commentable
  end

  test "admin may request assist on another user's submission" do
    enable_llm_assist!
    james_sub = submissions(:add1_by_james)
    sign_in_as("admin", "admin")
    assert_difference "Comment.count", 1 do
      post llm_assist_submission_comments_path(submission_id: james_sub.id),
           params: { model: "stub-model" }, as: :turbo_stream
    end
    assert_response :success
  end

  test "llm_assist rejects a model that is not registered instead of raising" do
    enable_llm_assist!
    sign_in_as("john", "hello")
    assert_no_difference "Comment.count" do
      post llm_assist_submission_comments_path(submission_id: @sub.id),
           params: { model: "no-such-model" }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_match(/LLM Assist Error/, response.body)
  end

  test "llm_assist modal sanitizes the model-written body but keeps the trusted header" do
    comment = @sub.comments.create!(
      user: users(:john), kind: "llm_assist", status: "ok", llm_model: "m", cost: 10,
      title: "Assistance by m",
      body: "## Hint\n\n<img src=x onerror=\"alert(1)\">\n\n" \
            "[link](javascript:alert(2))\n\n" \
            "<div class='alert alert-danger'>Request failed</div>"
    )
    sign_in_as("admin", "admin")
    get submission_comment_path(@sub, comment), as: :turbo_stream
    assert_response :success
    assert_no_match(/onerror/, response.body)
    assert_no_match(/javascript:/, response.body)
    assert_match(%r{<h2>Hint</h2>}, response.body)
    assert_match(/alert-danger/, response.body)          # server-written error block survives
    assert_match(%r{<script>\s*hljs\.highlightAll}, response.body)  # trusted header keeps its script, unescaped
    assert_match(%r{<div class='alert alert-info'>}, response.body)
  end

  # ------------------------------------------------------------
  # LLM assist — picker guards
  # ------------------------------------------------------------

  test "llm_assist is refused while an earlier request on the submission is still processing" do
    enable_llm_assist!
    @sub.comments.create!(user: users(:john), kind: 'llm_assist', status: 'processing', llm_model: 'stub-model',
                          title: 't', body: 'b', cost: 0)
    sign_in_as("john", "hello")
    assert_no_difference "Comment.count" do
      post llm_assist_submission_comments_path(submission_id: @sub.id), params: { model: "stub-model" }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_match(/still running/i, response.body)
  end

  test "llm_assist is refused on a submission that already has full score" do
    enable_llm_assist!
    @sub.update_columns(points: 100)
    sign_in_as("john", "hello")
    assert_no_difference "Comment.count" do
      post llm_assist_submission_comments_path(submission_id: @sub.id), params: { model: "stub-model" }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_match(/full score/i, response.body)
  end

  test "the picker shows the refusal and a disabled Get instead of an active button" do
    enable_llm_assist!
    @sub.comments.create!(user: users(:john), kind: 'llm_assist', status: 'processing', llm_model: 'stub-model',
                          title: 't', body: 'b', cost: 0)
    sign_in_as("john", "hello")
    get submission_path(@sub)
    assert_response :success
    assert_select "form button[disabled]", text: "Get"
    assert_match(/still running/i, response.body)
  end

  test "refreshing the comments also refreshes the picker so a finished request re-enables Get" do
    enable_llm_assist!
    sign_in_as("john", "hello")
    get submission_comments_path(@sub), as: :turbo_stream
    assert_response :success
    assert_match(/turbo-stream action="replace" target="llm_assist_picker"/, response.body)
  end

  test "the AI confirm dialog shows what was lost so far and the spending limit" do
    enable_llm_assist!
    sign_in_as("john", "hello")
    get submission_path(@sub)
    assert_response :success
    assert_match(/Lost on this problem so far: 0 \(hints 0, AI help 0\)\./, response.body)
    assert_match(/AI help on this problem stops once you have spent 100 points; you have spent 0\./, response.body)
  end

  test "the hint confirm dialog shows what was lost so far" do
    sign_in_as("john", "hello")
    get direct_edit_problem_submissions_path(problem_id: problems(:prob_add).id)
    assert_response :success
    assert_match(/Confirm getting a hint/, response.body)
    assert_match(/Lost on this problem so far: 0 \(hints 0, AI help 0\)\./, response.body)
  end

  test "the confirm dialog quotes the configured price" do
    enable_llm_assist!
    set_grader_config('system.llm_assist_cost', 7)
    sign_in_as("john", "hello")
    get submission_path(@sub)
    assert_response :success
    # the confirm text is JSON-encoded inside data-turbo-confirm, so the line
    # break before the number is a literal backslash-n
    assert_match(/7 points\. If your final score/, response.body)
    assert_no_match(/10 points\. If your final score/, response.body)
  end

  test "the confirm dialog tells an admin that a request on a student's submission is free; the owner still sees the price" do
    enable_llm_assist!
    sign_in_as("admin", "admin")
    get submission_path(@sub)
    assert_response :success
    assert_match(/This request does not reduce the/, response.body)
    assert_no_match(/10 points\. If your final score/, response.body)

    sign_in_as("john", "hello")
    get submission_path(@sub)
    assert_match(/10 points\. If your final score/, response.body)
    assert_no_match(/This request does not reduce the/, response.body)
  end

  # ------------------------------------------------------------
  # GitHub #50 vectors 3 and 4 — editor-typed titles and bodies are shown as
  # text (title) or sanitized markdown (body) everywhere they surface: the
  # comment list, the create toast, the View modal, the hint modal.
  # ------------------------------------------------------------
  XSS_TITLE = %(t <img src=x onerror=alert(1)>)

  test "comment list shows an editor's title as text, never as markup" do
    @sub.comments.create!(user: users(:admin), kind: "comment", title: XSS_TITLE, body: "b")
    sign_in_as("admin", "admin")
    get submission_comments_path(@sub), as: :turbo_stream
    assert_response :success
    assert_no_match(/<img/, response.body)
    assert_includes response.body, "t &lt;img src=x onerror=alert(1)&gt;"
  end

  test "a running AI assist shows its spinner from its status, not from markup in the title" do
    @sub.comments.create!(user: users(:john), kind: "llm_assist", status: "processing", llm_model: "m", cost: 0,
                          title: "AI m is thinking <b>x</b>", body: "wait")
    sign_in_as("admin", "admin")
    get submission_comments_path(@sub), as: :turbo_stream
    assert_response :success
    assert_match(/spinner-border/, response.body)
    assert_no_match(%r{<b>x</b>}, response.body)
  end

  test "llm_assist stores a plain-text placeholder title" do
    enable_llm_assist!
    sign_in_as("john", "hello")
    post llm_assist_submission_comments_path(submission_id: @sub.id), params: { model: "stub-model" }, as: :turbo_stream
    assert_response :success
    assert_equal "AI stub-model is thinking", Comment.order(:id).last.title
  end

  test "create toast shows the new comment's title as text" do
    sign_in_as("admin", "admin")
    post submission_comments_path(@sub), params: { comment_title: XSS_TITLE, comment_body: "b" }, as: :turbo_stream
    assert_response :created
    assert_no_match(/<img/, response.body)
    assert_includes response.body, "&lt;img src=x onerror=alert(1)&gt;"
  end

  test "comment modal escapes the title and sanitizes the body, keeping staff HTML" do
    c = @sub.comments.create!(user: users(:admin), kind: "comment", title: XSS_TITLE,
                              body: %(see <a href="/x.pdf" target="_blank">x</a> <script>alert(3)</script>))
    sign_in_as("admin", "admin")
    get submission_comment_path(@sub, c), as: :turbo_stream
    assert_response :success
    assert_no_match(/<img|<script>alert/, response.body)   # the stream's own show() script is fine
    assert_includes response.body, "Comment: t &lt;img src=x onerror=alert(1)&gt;"
    assert_includes response.body, '<a href="/x.pdf" target="_blank">x</a>'
  end

  test "hint modal sanitizes the hint body" do
    @hint.update!(body: %(tip <b>bold</b> <script>alert(4)</script>))
    sign_in_as("john", "hello")
    get problem_hint_path(problem_id: @prob.id, id: @hint.id), as: :turbo_stream
    assert_response :success
    assert_no_match(/<script>alert/, response.body)   # the stream's own show() script is fine
    assert_includes response.body, "<b>bold</b>"
  end
end
