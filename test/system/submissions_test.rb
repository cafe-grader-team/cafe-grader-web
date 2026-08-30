require "application_system_test_case"

class SubmissionsTest < ApplicationSystemTestCase
  # test "visiting the index" do
  #   visit users_url
  #
  #   assert_selector "h1", text: "User"
  # end

  test "add new submission" do
    #admin can add new submission regardless of availability of the problem
    login('admin','admin')
    visit direct_edit_problem_submissions_path(problems(:prob_sub))
    assert_text 'Latest Submission Status'
    find('.ace_text-input',visible: false).set "test code (will cause compilation error)"
    click_on 'Submit'
    page.accept_confirm
    assert_text 'less than a minute ago'
    visit logout_main_path

    #normal user can submit available problem
    login('john','hello')
    visit direct_edit_problem_submissions_path(problems(:prob_add))
    assert_text 'Latest Submission Status'
    find('.ace_text-input',visible: false).set "test code (will cause compilation error)"
    click_on 'Submit'
    page.accept_confirm
    assert_text 'less than a minute ago'
    visit logout_main_path

    #but not unavailable problem
    login('john','hello')
    visit direct_edit_problem_submissions_path(problems(:prob_sub))
    assert_text 'You are not authorized'
  end

  test "admin view submissions" do
    login('admin','admin')

    #view own submission
    within 'header' do
      click_on 'Submission'
      click_link 'View'
    end
    # the old "Go" button is gone — a select2 problem chooser now navigates on pick
    choose_submission_problem 'add_full_name'

    #click the first <a> item in the table
    first('table a').click
    assert_text "Submission Detail"
    assert_text "Grading Task Status"

    #view other submission of available problem
    within 'header' do
      click_on 'Manage'
      click_on 'Problem'
    end

    row = find('tr', text: 'add_full_name')
    within row do
      click_on 'Stat'
    end

    assert_text "Submissions"
    within find('tr', text: 'john') do
      first('a').click
    end
    assert_text "Submission Detail"
    assert_text "Grading Task Status"

    #view  other submission of unavailable problem
    visit submission_path( submissions(:sub1_by_james) )
    assert_text "Submission Detail"
    assert_text "Grading Task Status"
  end

  test "user view submissions" do
    login('john','hello')

    #view own submission
    within 'header' do
      click_on 'Submission'
      click_on 'View'
    end
    # the old "Go" button is gone — a select2 problem chooser now navigates on pick
    choose_submission_problem 'add_full_name'

    #click the first <a> item in the table
    first('table a').click
    assert_text "Submission Detail"
    assert_text "Grading Task Status"

    #view other submission of available problem
    GraderConfiguration.where(key: 'right.user_view_submission').update(value: 'true')

    #using direct link
    visit submission_path( submissions(:add1_by_james) )
    assert_text "Submission Detail"
    assert_text "Grading Task Status"

    #view admin's submission of available problem
    #using direct link
    visit submission_path( submissions(:add1_by_admin) )
    assert_text "Submission Detail"
    assert_text "Grading Task Status"

    #view  other submission of unavailable problem
    visit submission_path( submissions(:sub1_by_james) )
    assert_text "You are not authorized"

    #view  admin's submission of unavailable problem
    login('john','hello')
    visit submission_path( submissions(:sub1_by_admin) )
    assert_text "You are not authorized"

    #view other submission of available problem, right not allow
    GraderConfiguration.where(key: 'right.user_view_submission').update(value: 'false')
    login('john','hello')
    visit submission_path( submissions(:add1_by_james) )
    assert_text "You are not authorized"
  end

  def login(username,password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end

  # Pick a problem from the submissions-index select2 chooser (id
  # #submission_problems), which navigates to that problem's submissions on change.
  def choose_submission_problem(text)
    find('#submission_problems + .select2-container').click
    find('.select2-results__option', text: text).click
  end
end
