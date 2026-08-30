require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  # test "visiting the index" do
  #   visit users_url
  #
  #   assert_selector "h1", text: "User"
  # end

  test "add new user shows in the user list" do
    login('admin','admin')
    within 'header' do
      click_on 'Manage'
      click_on 'Users', match: :first
    end

    assert_text "Users"
    assert_text "Add User"

    click_on "Add User", match: :first
    fill_in 'Login', with: 'test1'
    fill_in 'Full name', with: 'test1 McTestface'
    fill_in 'e-mail', with: 'a@a.com'
    fill_in 'Password', with: 'abcdef'
    fill_in 'Password confirmation', with: 'abcdef'

    click_on 'Create'

    assert_text 'User was successfully created'
    # the index DataTable initialises on full page load and fetches rows via
    # AJAX; reload the index so it populates, then give the AJAX time
    visit user_admin_index_path
    assert_text 'a@a.com', wait: 10
    assert_text 'test1 McTestface'
    # Editing a user (user_admin#update — alias/remark persistence) is covered at
    # the controller level by UsersControllerTest "admin can update a user's remark
    # via user_admin#update". The edit page's form submission is unreliable to
    # drive under Selenium (the prominent "Save Changes" header button is outside
    # the form via an HTML5 form= association), so it isn't asserted here.
  end

  test "add multiple users" do
    login 'admin', 'admin'
    within 'header' do
      click_on 'Manage'
      click_on 'Users', match: :first
    end

    click_on 'Import Users', match: :first
    find(:css, 'textarea').fill_in with:"abc1,Boaty McBoatface,abcdef,alias1,remark1,\nabc2,Boaty2 McSecond,acbdef123,aias2,remark2"
    click_on 'Create following users'

    # the index DataTable initialises on full page load; reload so it populates
    visit user_admin_index_path
    assert_text('remark1', wait: 10)
    assert_text('remark2', wait: 10)
  end

  test "grant admin right" do
    login 'admin', 'admin'
    within 'header' do
      click_on 'Manage'
      click_on 'Users', match: :first
    end

    click_on "Admins"
    # the old 'login' text field is now a per-role select2; pick john in the admin panel, then grant
    find('#admin_user_id + .select2-container').click
    find('.select2-container--open .select2-results__option', text: 'john').click
    within(:xpath, "//form[.//select[@id='admin_user_id']]") { click_on 'Grant' }

    visit logout_main_path
    login 'john','hello'
    within 'header' do
      click_on 'Manage'
      click_on 'Problem', match: :first
    end
    assert_text "All Off"
  end

  test "try using admin from normal user" do
    login 'admin','admin'
    visit  bulk_manage_user_admin_index_path
    assert_current_path bulk_manage_user_admin_index_path
    visit logout_main_path

    login 'jack','morning'
    visit  bulk_manage_user_admin_index_path
    assert_text 'You are not authorized'
    assert_current_path list_main_path

    login 'james','morning'
    visit  new_list_user_admin_index_path
    assert_text 'You are not authorized'
    assert_current_path list_main_path
  end

  test "login then change password" do
    newpassword = '1234asdf'
    login 'john', 'hello'
    visit profile_users_path

    fill_in 'user_password', with: newpassword
    fill_in 'user_password_confirmation', with: newpassword

    click_on 'Save changes'
    # wait for the password change to persist before logging out (else the logout
    # can race the update and the old password still works). Explicit wait so a
    # slow turbo submit under load doesn't time out at the default ~2s.
    assert_text 'Updated successfully', wait: 10

    visit logout_main_path
    # the old password should now fail — don't use the success-asserting login helper
    visit root_path
    fill_in "Login", with: 'john'
    fill_in "Password", with: 'hello'
    click_on "Login"
    assert_text 'Wrong password', wait: 10

    login 'john', newpassword
    assert_text "MAIN"
    assert_text "Submission"
  end

  def login(username,password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end
end
