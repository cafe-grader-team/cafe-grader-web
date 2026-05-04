require "test_helper"

class SitesControllerTest < ActionDispatch::IntegrationTest
  # Note: SitesController is part of the legacy multi-site contest feature.
  # If `contest.multisites` is unused in production, the entire
  # `sites_controller.rb` + `site_controller.rb` pair could be deleted.
  # These tests exercise only the basic admin-CRUD smoke shape.

  # --- Authorization ---

  test "unauthenticated cannot list sites" do
    get sites_path
    assert_redirected_to login_main_path
  end

  test "normal user cannot list sites" do
    sign_in_as("john", "hello")
    get sites_path
    assert_redirected_to list_main_path
  end

  test "group editor cannot list sites" do
    sign_in_as("mary", "mary")
    get sites_path
    assert_redirected_to list_main_path
  end

  # --- Admin paths ---

  test "admin can list sites" do
    sign_in_as("admin", "admin")
    get sites_path
    assert_response :success
  end

  test "admin can view new site form" do
    sign_in_as("admin", "admin")
    get new_site_path
    assert_response :success
  end

  test "admin can show a site" do
    sign_in_as("admin", "admin")
    get site_path(sites(:first_site))
    assert_response :success
  end

  test "admin can edit a site" do
    sign_in_as("admin", "admin")
    get edit_site_path(sites(:first_site))
    assert_response :success
  end

  test "admin can destroy a site" do
    sign_in_as("admin", "admin")
    target = Site.create!(name: "Throwaway", started: false)
    assert_difference "Site.count", -1 do
      delete site_path(target)
    end
  end
end
