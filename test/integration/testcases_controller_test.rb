require "test_helper"

class TestcasesControllerTest < ActionDispatch::IntegrationTest
  # `testcases#download_input/sol` use Active Storage `inp_file.download` which
  # requires an actual blob attachment. Fixtures only set the `input`/`sol`
  # text columns, not the attachment. We therefore exercise auth on those
  # endpoints but not the file body. `show_problem` doesn't need an
  # attachment so we cover it more fully.

  # --- Authorization on show_problem ---

  test "unauthenticated cannot show problem testcases" do
    get show_problem_testcases_path(problem_id: problems(:prob_add).id)
    assert_redirected_to login_main_path
  end

  test "normal user cannot show problem testcases when right.view_testcase=false (default)" do
    set_grader_config("right.view_testcase", "false")
    problems(:prob_add).update!(view_testcase: false)
    sign_in_as("john", "hello")
    get show_problem_testcases_path(problem_id: problems(:prob_add).id)
    assert_response :redirect
  end

  test "normal user can show problem testcases when right.view_testcase=true" do
    set_grader_config("right.view_testcase", "true")
    problems(:prob_add).update!(view_testcase: true)
    sign_in_as("john", "hello")
    get show_problem_testcases_path(problem_id: problems(:prob_add).id)
    assert_response :success
  end

  test "admin can always show problem testcases" do
    sign_in_as("admin", "admin")
    get show_problem_testcases_path(problem_id: problems(:prob_add).id)
    assert_response :success
  end

  # --- Authorization on download_input/sol (no body assertion) ---

  test "unauthenticated cannot download testcase input" do
    get download_input_testcase_path(testcases(:tc_add_1))
    assert_redirected_to login_main_path
  end

  test "normal user cannot download testcase input when right.view_testcase=false" do
    set_grader_config("right.view_testcase", "false")
    sign_in_as("john", "hello")
    get download_input_testcase_path(testcases(:tc_add_1))
    assert_response :redirect
  end

  # --- Tiers (issues #18 and #59): preview for students, whole files for staff ---

  def allow_student_view
    set_grader_config("right.view_testcase", "true")
    problems(:prob_add).update!(view_testcase: true)
  end

  def attach_files(tc, input_bytes: 5000)
    tc.inp_file.attach(io: StringIO.new("A" * input_bytes + "\n"), filename: "in.txt")
    tc.ans_file.attach(io: StringIO.new("3\n"), filename: "sol.txt")
  end

  test "student sees the first 2048 bytes of a big file, a small file whole, and no download button" do
    allow_student_view
    attach_files(testcases(:tc_add_1))
    sign_in_as("john", "hello")
    get show_problem_testcases_path(problems(:prob_add))
    assert_response :success
    assert_select "#testcase-tier-note", text: /first 2 KB of each file/
    assert_select "textarea", text: /A{2048}/
    assert_no_match(/A{2049}/, response.body)
    assert_select ".badge", text: "truncated", count: 1
    assert_select "textarea", text: /\A\s*3\s*\z/
    assert_select "a", text: /Download/, count: 0
  end

  test "download is refused below the full tier, including when only the problem's own flag is off" do
    allow_student_view
    attach_files(testcases(:tc_add_1))
    sign_in_as("john", "hello")
    get download_input_testcase_path(testcases(:tc_add_1))
    assert_redirected_to list_main_path
    get download_sol_testcase_path(testcases(:tc_add_1))
    assert_redirected_to list_main_path

    problems(:prob_add).update!(view_testcase: false)
    get download_input_testcase_path(testcases(:tc_add_1))
    assert_redirected_to list_main_path
    get show_problem_testcases_path(problems(:prob_add))
    assert_redirected_to list_main_path
  end

  test "admin gets download buttons on the page and the whole file from the download" do
    attach_files(testcases(:tc_add_1))
    sign_in_as("admin", "admin")
    get show_problem_testcases_path(problems(:prob_add))
    assert_response :success
    assert_select "a", text: /Download/, minimum: 2
    assert_no_match(/A{2049}/, response.body)   # the page itself still shows the prefix
    get download_input_testcase_path(testcases(:tc_add_1))
    assert_response :success
    assert_equal 5001, response.body.bytesize
  end

  test "a preview size of 0 shows whole files" do
    allow_student_view
    set_grader_config("ui.testcase_preview_bytes", "0")
    attach_files(testcases(:tc_add_1), input_bytes: 3000)
    sign_in_as("john", "hello")
    get show_problem_testcases_path(problems(:prob_add))
    assert_response :success
    assert_match(/A{3000}/, response.body)
    assert_select ".badge", text: "truncated", count: 0
  ensure
    reset_grader_config_cache
  end

  test "run-time data files: prefix on the page for a student, download only for the full tier" do
    allow_student_view
    ds = problems(:prob_add).live_dataset
    ds.data_files.attach(io: StringIO.new("D" * 3000), filename: "words.txt")
    df_id = ds.data_files.first.id

    sign_in_as("john", "hello")
    get show_problem_testcases_path(problems(:prob_add))
    assert_response :success
    assert_select "#data-files", text: /words\.txt/
    assert_select "#data-files textarea", text: /D{2048}/
    assert_no_match(/D{2049}/, response.body)
    get download_data_file_testcases_path(problems(:prob_add), df_id)
    assert_redirected_to list_main_path

    sign_in_as("admin", "admin")
    get download_data_file_testcases_path(problems(:prob_add), df_id)
    assert_response :success
    assert_equal 3000, response.body.bytesize
  end
end
