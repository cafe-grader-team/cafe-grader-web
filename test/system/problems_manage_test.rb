require "application_system_test_case"

class ProblemsManageTest < ApplicationSystemTestCase
  setup do
    @prob_add = problems(:prob_add)
    @prob_sub = problems(:prob_sub)
  end

  test "visit manage page and see problems loaded via AJAX" do
    login("admin", "admin")
    visit manage_problems_path

    assert_text "Bulk Manage Problems"
    # DataTable loads via AJAX — wait for checkboxes to appear
    assert_selector "#prob-#{@prob_add.id}"
    assert_selector "#prob-#{@prob_sub.id}"
  end

  test "set available to yes" do
    login("admin", "admin")
    visit manage_problems_path

    find("#prob-#{@prob_sub.id}").check
    check "change_enable"
    choose "yes"
    click_on "Apply to Selected"
    # the bulk action submits via turbo_stream and updates the DB before the
    # response toast is appended — wait for the toast so we don't read the DB
    # before the async submission lands
    assert_selector ".toast", wait: 10

    assert @prob_sub.reload.available?, "Expected problem to become available"
  end

  test "set available to no" do
    login("admin", "admin")
    visit manage_problems_path

    find("#prob-#{@prob_add.id}").check
    check "change_enable"
    choose "no"
    click_on "Apply to Selected"
    # the bulk action submits via turbo_stream and updates the DB before the
    # response toast is appended — wait for the toast so we don't read the DB
    # before the async submission lands
    assert_selector ".toast", wait: 10

    assert_not @prob_add.reload.available?, "Expected problem to become unavailable"
  end

  test "change date added" do
    login("admin", "admin")
    visit manage_problems_path

    find("#prob-#{@prob_add.id}").check
    check "change_date_added"
    # Set value directly — TempusDominus may intercept normal input
    page.execute_script("document.getElementById('date_added').value = '2025-01-15'")
    click_on "Apply to Selected"
    # the bulk action submits via turbo_stream and updates the DB before the
    # response toast is appended — wait for the toast so we don't read the DB
    # before the async submission lands
    assert_selector ".toast", wait: 10

    assert_equal Date.new(2025, 1, 15), @prob_add.reload.date_added.to_date
  end

  test "add tags to problem" do
    login("admin", "admin")
    visit manage_problems_path

    find("#prob-#{@prob_add.id}").check
    check "add_tags"
    select2_select "easy", from: "tag_ids"
    click_on "Apply to Selected"

    assert_includes @prob_add.reload.tags.pluck(:name), "easy"
  end

  test "add problem to group" do
    login("admin", "admin")
    visit manage_problems_path

    find("#prob-#{@prob_add.id}").check
    check "add_group"
    select2_select "GroupA", from: "group_id"
    click_on "Apply to Selected"

    assert_includes groups(:group_a).reload.problem_ids, @prob_add.id
  end

  test "set permitted languages" do
    login("admin", "admin")
    visit manage_problems_path

    assert_selector "#prob-#{@prob_add.id}"
    find("#prob-#{@prob_add.id}").check
    check "set_languages"
    select2_select "c", from: "lang_ids"
    select2_select "cpp", from: "lang_ids"
    click_on "Apply to Selected"
    # the bulk action submits via turbo_stream and updates the DB before the
    # response toast is appended — wait for the toast so we don't read the DB
    # before the async submission lands
    assert_selector ".toast", wait: 10

    permitted = @prob_add.reload.permitted_lang.to_s.split
    assert_includes permitted, "c"
    assert_includes permitted, "cpp"
  end

  test "apply action to multiple individually selected problems" do
    login("admin", "admin")
    visit manage_problems_path

    find("#prob-#{@prob_add.id}").check
    find("#prob-#{@prob_sub.id}").check

    check "change_enable"
    choose "no"
    click_on "Apply to Selected"
    # the bulk action submits via turbo_stream and updates the DB before the
    # response toast is appended — wait for the toast so we don't read the DB
    # before the async submission lands
    assert_selector ".toast", wait: 10

    assert_not @prob_add.reload.available?, "Expected prob_add to become unavailable"
    assert_not @prob_sub.reload.available?, "Expected prob_sub to become unavailable"
  end

  test "select all then apply action" do
    login("admin", "admin")
    visit manage_problems_path

    # Wait for table to finish loading
    assert_selector "#prob-#{@prob_add.id}"
    find("#select_all").check

    check "change_enable"
    choose "yes"
    click_on "Apply to Selected"
    # the bulk action submits via turbo_stream and updates the DB before the
    # response toast is appended — wait for the toast so we don't read the DB
    # before the async submission lands
    assert_selector ".toast", wait: 10

    Problem.where(id: [@prob_add.id, @prob_sub.id]).each do |p|
      assert p.reload.available?, "Expected problem #{p.name} to be available"
    end
  end

  private

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end

  def select2_select(text, from:)
    find("##{from} + .select2-container").click
    # Scope the search field + results to the widget we just opened. The page
    # has several select2 widgets, and multi-selects (tag_ids, lang_ids) keep an
    # always-visible .select2-search__field, so an unscoped find is ambiguous.
    # Only the open widget carries .select2-container--open.
    find(".select2-container--open .select2-search__field").set(text)
    # exact_text so e.g. searching "c" picks the "c" option, not "cpp" too
    find(".select2-container--open .select2-results__option", exact_text: text).click
  end
end
