require "test_helper"

class GradersControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get grader_processes_path
    assert_redirected_to login_main_path
  end

  test "normal user is redirected" do
    sign_in_as("john", "hello")
    get grader_processes_path
    assert_redirected_to list_main_path
  end

  test "group editor is redirected" do
    sign_in_as("mary", "mary")
    get grader_processes_path
    assert_redirected_to list_main_path
  end

  # --- Admin happy paths ---

  test "admin can access graders index" do
    sign_in_as("admin", "admin")
    get grader_processes_path
    assert_response :success
  end

  test "recent submissions honors a whitelisted limit param" do
    sign_in_as("admin", "admin")
    get grader_processes_path(limit: 100)
    assert_response :success
    assert_match "Last 100 submissions", response.body
  end

  test "recent submissions falls back to 20 on a bogus limit param" do
    sign_in_as("admin", "admin")
    get grader_processes_path(limit: 99999)
    assert_response :success
    assert_match "Last 20 submissions", response.body
  end

  test "admin can access queues dashboard" do
    sign_in_as("admin", "admin")
    get queues_grader_processes_path
    assert_response :success
  end

  # --- Error-job management ---

  test "admin can retry a single error job" do
    sign_in_as("admin", "admin")
    job = jobs(:job_error)
    assert_equal "error", job.status
    post retry_error_job_grader_processes_path, params: { job_id: job.id }, as: :turbo_stream
    assert_response :success
    assert_equal "wait", job.reload.status
  end

  test "admin can retry all error jobs" do
    sign_in_as("admin", "admin")
    Job.where(status: :error).count > 0  # baseline
    post retry_all_error_jobs_grader_processes_path, as: :turbo_stream
    assert_response :success
    assert_equal 0, Job.where(status: :error).count
  end

  test "admin can clear all error jobs" do
    sign_in_as("admin", "admin")
    initial_count = Job.where(status: :error).count
    assert_operator initial_count, :>, 0, "fixture must include at least one :error job"
    post clear_all_error_jobs_grader_processes_path, as: :turbo_stream
    assert_response :success
    assert_equal 0, Job.where(status: :error).count
  end
end
