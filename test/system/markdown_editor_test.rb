require "application_system_test_case"

# The markdown-editor Stimulus controller: Ace replaces the textarea, edits
# flow back into it (so the form saves what you typed), and Preview renders
# through the server.
class MarkdownEditorTest < ApplicationSystemTestCase
  test "viva briefing is edited in Ace, syncs to the textarea, and previews" do
    login("admin", "admin")
    visit edit_problem_path(problems(:prob_viva))

    # scope to the briefing's editor (the viva layout has several on the page)
    briefing_editor = find("textarea#problem_viva_prompt", visible: false).ancestor("[data-controller='markdown-editor']")
    within briefing_editor do
      assert_selector ".ace_editor", wait: 10
      # Ace's hidden textarea receives keyboard input
      find(".ace_text-input", visible: false).send_keys([:control, "a"], "# Rubric\n\n| a | b |\n|---|---|\n| 1 | 2 |")
      textarea = find("textarea#problem_viva_prompt", visible: false)
      assert_includes textarea.value, "# Rubric"

      click_on "Preview"
      assert_selector ".markdown-editor__preview h1", text: "Rubric", wait: 10
      assert_selector ".markdown-editor__preview table"

      click_on "Edit"
      assert_selector ".ace_editor"
    end
  end

  def login(username, password)
    visit root_path
    fill_in "Login", with: username
    fill_in "Password", with: password
    click_on "Login"
    assert_current_path list_main_path, wait: 5
  end
end
