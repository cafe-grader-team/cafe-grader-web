require "application_system_test_case"

class UserAdminAdminPanelTest < ApplicationSystemTestCase
  test "grant and revoke admin role via the admin panel" do
    login 'admin', 'admin'
    visit admin_user_admin_index_path

    assert_text 'Administrators'
    assert_text 'TAs'

    # admin user (from fixtures) is already in the admin table
    within '#admin-table' do
      assert_text 'admin'
      assert_no_text 'john'
    end

    # grant admin to john through the Admin panel's select2 dropdown
    select2_select '[john]', from: 'admin_user_id'
    within('form[data-role-table="admin-table"]') { click_on 'Grant' }

    within '#admin-table' do
      assert_text 'john'
    end
    assert User.find_by_login('john').roles.exists?(name: 'admin')

    # revoke john from the admin table
    within('#admin-table') { within('tr', text: 'john') { click_on 'Revoke' } }

    within '#admin-table' do
      assert_no_text 'john'
    end
    assert_not User.find_by_login('john').roles.exists?(name: 'admin')
  end

  test "grant and revoke ta role via the ta panel" do
    login 'admin', 'admin'
    visit admin_user_admin_index_path

    within '#ta-table' do
      assert_no_text 'mary'
    end

    # grant TA to mary through the TA panel's select2 dropdown
    select2_select '[mary]', from: 'ta_user_id'
    within('form[data-role-table="ta-table"]') { click_on 'Grant' }

    within '#ta-table' do
      assert_text 'mary'
    end
    assert User.find_by_login('mary').roles.exists?(name: 'ta')

    # revoke
    within('#ta-table') { within('tr', text: 'mary') { click_on 'Revoke' } }

    within '#ta-table' do
      assert_no_text 'mary'
    end
    assert_not User.find_by_login('mary').roles.exists?(name: 'ta')
  end

  test "both select2 dropdowns are independently usable" do
    login 'admin', 'admin'
    visit admin_user_admin_index_path

    # admin-side dropdown shows users including 'john'
    find('#admin_user_id + .select2-container').click
    find('.select2-search__field').fill_in(with: 'john')
    assert_selector '.select2-results__option', text: '[john]'
    # close the dropdown
    find('body').send_keys(:escape)

    # ta-side dropdown also works
    find('#ta_user_id + .select2-container').click
    find('.select2-search__field').fill_in(with: 'mary')
    assert_selector '.select2-results__option', text: '[mary]'
    find('body').send_keys(:escape)
  end

  def login(username, password)
    visit root_path
    fill_in 'Login', with: username
    fill_in 'Password', with: password
    click_on 'Login'
    # Login form uses Turbo, so Capybara may not auto-sync. Wait for the
    # post-login landing page to appear before returning.
    assert_current_path list_main_path, wait: 5
  end

  def select2_select(text, from:)
    find("##{from} + .select2-container").click
    find('.select2-search__field').fill_in(with: text)
    find('.select2-results__option', text: text).click
  end
end
