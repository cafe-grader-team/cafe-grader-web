require "test_helper"

# The "Submission Detail" card (submissions/show) and the "Viva Info" card
# (viva_sessions/show) share their User and Problem rows
# (submissions/_who_and_what_rows): the author's name goes to the owner and the
# problem's staff, a peer who may open the page sees "hidden", and only an
# admin gets the link to the admin-only user stat page (design 2026-11-18).
class SubmissionAuthorVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @sub  = submissions(:add1_by_john)
    @john = users(:john)
  end

  teardown { reset_grader_config_cache }

  def pages
    [submission_path(@sub), viva_submission_path(@sub)]
  end

  test "the owner sees their own name without a stat link, on both pages" do
    sign_in_as("john", "hello")
    pages.each do |page|
      get page
      assert_response :success, page
      assert_includes response.body, @john.full_name, page
      assert_select "a[href=?]", stat_user_admin_path(@john), false, page
    end
  end

  test "an admin sees the name with the stat link, on both pages" do
    sign_in_as("admin", "admin")
    pages.each do |page|
      get page
      assert_response :success, page
      assert_includes response.body, @john.full_name, page
      assert_select "a[href=?]", stat_user_admin_path(@john), { text: @john.login }, page
    end
  end

  test "a non-admin editor of the problem's group sees the name without a stat link, on both pages" do
    set_grader_config("system.use_problem_group", "true")
    sign_in_as("mary", "mary")
    pages.each do |page|
      get page
      assert_response :success, page
      assert_includes response.body, @john.full_name, page
      assert_select "a[href=?]", stat_user_admin_path(@john), false, page
    end
  end

  test "another student allowed to view sees 'hidden' instead of the name, on both pages" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.user_view_submission", "true")
    @sub.problem.update!(view_submission: true)
    sign_in_as("james", "morning")
    pages.each do |page|
      get page
      assert_response :success, page
      assert_not_includes response.body, @john.full_name, page
      assert_not_includes response.body, ">#{@john.login}<", page
      assert_select ".text-secondary.fst-italic", { text: "hidden" }, page
    end
  end

  test "both pages show the shared problem block" do
    sign_in_as("admin", "admin")
    pages.each do |page|
      get page
      assert_select "[data-controller~='problem-name'] .font-monospace", { text: /#{@sub.problem.name}/ }, page
      assert_select "a[href=?]", edit_problem_path(@sub.problem), true, page
    end
  end
end
