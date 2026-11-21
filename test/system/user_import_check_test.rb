require "application_system_test_case"

class UserImportCheckTest < ApplicationSystemTestCase
  test "Check shows the result without saving; editing marks it stale; Create still works" do
    login('admin', 'admin')
    visit new_list_user_admin_index_path
    find('textarea[name="user_list"]').set("john,john,newpw\nnewbie7,New Bie,pass")
    click_on 'Check'
    assert_text '1 new account', wait: 10
    assert users(:john).reload.authenticated?('hello')

    find('textarea[name="user_list"]').set("john,john,newpw\nnewbie7,New Bie,pass\nnewbie8,X,pass")
    assert_text 'The list changed. Press Check again.'
    click_on 'Create following users'
    assert_text 'were created successfully', wait: 10
    assert User.find_by_login('newbie8')
  end

  test "the stale note shows only while the form differs from what was checked" do
    login('admin', 'admin')
    visit new_list_user_admin_index_path
    area = find('textarea[name="user_list"]')
    area.set("newbie9,New Bie,pass")
    click_on 'Check'
    assert_text '1 new account', wait: 10
    assert_selector '[data-user-admin--import-target="stale"].d-none', visible: :all
    area.set("newbie9,New Bie,pass2")
    assert_text 'The list changed. Press Check again.'
    area.set("newbie9,New Bie,pass")
    assert_no_text 'The list changed. Press Check again.'
  end

  private

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end
end
