require "test_helper"

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
