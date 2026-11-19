require "test_helper"
require "capybara/selenium/driver"

# Capybara 3.40.0 (the latest release; its master is the same on 2026-11-19)
# ends every Chrome session reset with the CDP call
# Storage.clearDataForOrigin(origin: '*'). Chrome 158 — the Chrome for
# Testing build Selenium Manager fetched on 2026-11-18 — rejects the wildcard
# ("invalid argument: * is not a valid URL"), so every system test errored in
# teardown although its assertions passed; Chrome 155 still accepted it.
# This does the same clearing without the wildcard: every cookie (the CDP
# call Capybara's own delete_all_cookies uses) and the app origin's local
# storage (the main list keeps its status filter there).
# test/system/system_test_reset_test.rb checks both are cleared.
# TODO(capybara): remove once a Capybara release stops sending origin '*'.
module ChromeResetWithoutWildcardOrigin
  private

  def execute_cdp(cmd, params = {})
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies")
    return unless params[:storageTypes].to_s.include?("local_storage")

    origin = Capybara.current_session.server&.base_url
    super("Storage.clearDataForOrigin", origin: origin, storageTypes: "local_storage") if origin
  end
end
Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeResetWithoutWildcardOrigin)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Headed Chrome by default so you can watch the run locally; set HEADLESS=1 for
  # headless. CI opts in to headless explicitly (HEADLESS: "1" in the job).
  using = ENV["HEADLESS"].present? ? :headless_chrome : :chrome

  driven_by :selenium, using: using, screen_size: [1400, 1400] do |options|
    # Disable Chrome's password manager and "password found in a data breach"
    # leak detection. Otherwise tests that change a password (e.g. the profile
    # change-password flow) trigger a native Chrome modal that blocks the page —
    # intermittently, since it depends on Chrome's leak check.
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_enabled", false)
    options.add_preference("profile.password_manager_leak_detection", false)
  end
end
