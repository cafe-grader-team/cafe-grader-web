require "test_helper"

class ProblemsControllerTest < ActionDispatch::IntegrationTest
  # --- Authorization ---

  test "unauthenticated user is redirected" do
    get problems_path
    assert_redirected_to login_main_path
  end

  test "normal user is redirected from problems index" do
    sign_in_as("john", "hello")
    get problems_path
    assert_redirected_to list_main_path
  end

  test "admin can access problems index" do
    sign_in_as("admin", "admin")
    get problems_path
    assert_response :success
  end

  test "group editor can access problems index" do
    sign_in_as("mary", "mary")
    get problems_path
    assert_response :success
  end

  # --- Read actions ---

  test "admin can edit problem" do
    sign_in_as("admin", "admin")
    get edit_problem_path(problems(:prob_add))
    assert_response :success
  end

  test "admin can view problem stat" do
    sign_in_as("admin", "admin")
    get stat_problem_path(problems(:prob_add))
    assert_response :success
  end

  test "admin can access manage page" do
    sign_in_as("admin", "admin")
    get manage_problems_path
    assert_response :success
  end

  test "problems without any dataset still appear on index" do
    sign_in_as("admin", "admin")
    # Build a Problem with no associated Dataset. The previous INNER JOIN
    # in problem_for_manage would silently drop this row from the list;
    # the LEFT JOIN should let it through.
    Problem.create!(name: "orphan", full_name: "Orphan Problem")
    get problems_path
    assert_response :success
    assert_match "orphan", response.body
  end

  test "admin can access import form" do
    sign_in_as("admin", "admin")
    get import_problems_path
    assert_response :success
  end

  test "admin can query problem manage as JSON" do
    sign_in_as("admin", "admin")
    post manage_query_problems_path, as: :json
    assert_response :success
  end

  # --- Write actions ---

  test "admin can create problem" do
    sign_in_as("admin", "admin")
    assert_difference "Problem.count" do
      post problems_path, params: {
        problem: { name: "newprob", full_name: "New Problem", full_score: 100 }
      }
    end
  end

  test "admin can quick_create problem" do
    sign_in_as("admin", "admin")
    assert_difference ["Problem.count", "Dataset.count"] do
      post quick_create_problems_path, params: { problem: { name: "qcprob" } }, as: :turbo_stream
    end
    prob = Problem.find_by(name: "qcprob")
    assert prob, "new problem should be persisted"
    assert prob.live_dataset, "new problem should have a live dataset assigned"
    # On success, quick_create redirects to the problems index with 303 See
    # Other so Turbo follows it and re-renders the list with the new row.
    # (Previously returned 200 with a turbo_stream toast, but that didn't
    # refresh the index because the listing isn't AJAX-driven.)
    assert_redirected_to problems_path
    assert_equal 303, @response.status
  end

  test "quick_create with invalid name does not create a problem" do
    sign_in_as("admin", "admin")
    assert_no_difference "Problem.count" do
      # blank name fails Problem validation
      post quick_create_problems_path, params: { problem: { name: "" } }, as: :turbo_stream
    end
    # On failure, the action renders a turbo_stream toast with
    # :unprocessable_entity (422) so Turbo treats the form submission as
    # rejected.
    assert_response :unprocessable_entity
  end

  test "admin can update problem" do
    sign_in_as("admin", "admin")
    p = problems(:prob_add)
    patch problem_path(p), params: {
      problem: { full_name: "Updated Name", permitted_lang: [] }
    }, as: :turbo_stream
    assert_equal "Updated Name", p.reload.full_name
  end

  test "admin can destroy problem" do
    sign_in_as("admin", "admin")
    prob = problems(:prob_sub)
    assert_difference "Problem.count", -1 do
      delete problem_path(prob)
    end
  end

  # --- Toggle endpoints ---

  test "admin can toggle problem availability" do
    sign_in_as("admin", "admin")
    p = problems(:prob_add)
    was = p.available
    post toggle_available_problem_path(p), as: :turbo_stream
    assert_equal !was, p.reload.available
  end

  test "group editor cannot toggle availability (admin only)" do
    sign_in_as("mary", "mary")
    p = problems(:prob_add)
    post toggle_available_problem_path(p), as: :turbo_stream
    # admin_authorization redirects non-admins
    assert_response :redirect
  end

  test "admin can toggle view_testcase" do
    sign_in_as("admin", "admin")
    p = problems(:prob_add)
    was = p.view_testcase
    post toggle_view_testcase_problem_path(p), as: :turbo_stream
    assert_equal !was, p.reload.view_testcase
  end

  # --- Bulk actions (admin only) ---

  test "admin can turn all problems off" do
    sign_in_as("admin", "admin")
    Problem.update_all(available: true)
    get turn_all_off_problems_path
    assert Problem.where(available: true).count == 0
  end

  test "admin can turn all problems on" do
    sign_in_as("admin", "admin")
    Problem.update_all(available: false)
    get turn_all_on_problems_path
    assert Problem.where(available: false).count == 0
  end

  test "non-admin cannot turn all problems off" do
    sign_in_as("mary", "mary")
    get turn_all_off_problems_path
    assert_response :redirect
  end

  # --- PDF visibility for viva problems ---
  #
  # The viva PDF is the interviewer's brief, not student-facing material.
  # Students must be denied; admins/editors/reporters keep access.
  # The 'attachment' type is a generic file slot and stays open.

  test "student is blocked from downloading viva problem PDF" do
    sign_in_as("john", "hello")
    get download_by_type_problem_path(problems(:prob_viva), 'statement')
    # Hits the error template with our PDF-specific message.
    assert_match(/statement[^<]{1,30}available/i, response.body)
  end

  test "student is blocked from downloading viva problem generated PDF" do
    sign_in_as("john", "hello")
    get download_by_type_problem_path(problems(:prob_viva), 'generated_statement')
    assert_match(/statement[^<]{1,30}available/i, response.body)
  end

  test "admin can pass the PDF gate on viva problem" do
    sign_in_as("admin", "admin")
    get download_by_type_problem_path(problems(:prob_viva), 'statement')
    # The PDF gate does NOT block admin; we land in the download path
    # (which then errors on the missing file — that's a different
    # error message, proving the gate didn't fire).
    refute_match(/statement[^<]{1,30}available/i, response.body)
  end

  test "student is NOT blocked from downloading regular (non-viva) PDF" do
    sign_in_as("john", "hello")
    get download_by_type_problem_path(problems(:prob_add), 'statement')
    refute_match(/statement[^<]{1,30}available/i, response.body)
  end

  test "PDF gate does not affect generic attachment downloads on viva problem" do
    sign_in_as("john", "hello")
    get download_by_type_problem_path(problems(:prob_viva), 'attachment')
    refute_match(/statement[^<]{1,30}available/i, response.body)
  end

  test "admin can pass the PDF gate on regular (non-viva) problem" do
    # Mirror of the student/non-viva case to confirm the gate doesn't
    # accidentally block admins anywhere.
    sign_in_as("admin", "admin")
    get download_by_type_problem_path(problems(:prob_add), 'statement')
    refute_match(/statement[^<]{1,30}available/i, response.body)
  end

  test "group editor can download viva PDF when problem is in their group" do
    # Group-based authorization only matters when use_problem_group is on.
    # Fixtures place mary (editor role) in group_a; we add prob_viva to
    # the same group at test time. Once mary is an editor of the problem,
    # can_edit_problem? short-circuits and the PDF gate lets her through.
    set_grader_config('system.use_problem_group', 'true')
    GroupProblem.create!(group: groups(:group_a), problem: problems(:prob_viva), enabled: true)
    sign_in_as("mary", "mary")
    get download_by_type_problem_path(problems(:prob_viva), 'statement')
    refute_match(/statement[^<]{1,30}available/i, response.body)
  end

  test "group reporter can download viva PDF when problem is in their group" do
    # james is in group_a with role 0 (user) in the fixture. Flip him
    # to reporter (role 1) for this test so can_report_problem? returns
    # true and the gate's reporter short-circuit fires. The unit test
    # covers the predicate orchestration; this asserts the same path
    # works end-to-end through the controller.
    set_grader_config('system.use_problem_group', 'true')
    GroupProblem.create!(group: groups(:group_a), problem: problems(:prob_viva), enabled: true)
    groups_users(:james_in_group_a).update!(role: 1)
    sign_in_as("james", "morning")
    get download_by_type_problem_path(problems(:prob_viva), 'statement')
    refute_match(/statement[^<]{1,30}available/i, response.body)
  end
end
