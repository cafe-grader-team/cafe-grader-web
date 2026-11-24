require "application_system_test_case"

# Guards the Chrome reset fix in application_system_test_case.rb: between
# tests the browser must lose its login cookie and the app's local storage
# (the main list keeps its status filter there).
class SystemTestResetTest < ApplicationSystemTestCase
  test "a session reset clears the login cookie and the app's local storage" do
    visit root_path
    fill_in "Login", with: "admin"
    fill_in "Password", with: "admin"
    click_on "Login"
    assert_current_path list_main_path, wait: 5
    page.execute_script("localStorage.setItem('reset-probe', '1')")
    assert_equal "1", page.evaluate_script("localStorage.getItem('reset-probe')")

    Capybara.reset_sessions!

    visit list_main_path
    assert_field "Login", wait: 5
    assert_nil page.evaluate_script("localStorage.getItem('reset-probe')")
  end
end
