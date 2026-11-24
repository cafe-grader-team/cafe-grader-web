require "test_helper"

# POST /markdown/preview — server-side render for the markdown-editor Preview
# pane — and the wiring of that editor onto the long prompt textareas.
class MarkdownControllerTest < ActionDispatch::IntegrationTest
  test "renders markdown to HTML for an admin" do
    sign_in_as("admin", "admin")
    post markdown_preview_path, params: { text: "# Rubric\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n~~old~~ *new*" }
    assert_response :success
    assert_match %r{<h1>Rubric</h1>}, response.body
    assert_match %r{<table>}, response.body          # tables on (rubrics use them)
    assert_match %r{<del>old</del>}, response.body   # strikethrough on
    assert_no_match %r{<html}, response.body         # bare fragment, no layout
  end

  test "renders for a group editor" do
    sign_in_as("mary", "mary")
    post markdown_preview_path, params: { text: "*hi*" }
    assert_response :success
    assert_match %r{<em>hi</em>}, response.body
  end

  test "escapes raw HTML in the preview instead of executing or dropping it" do
    sign_in_as("admin", "admin")
    post markdown_preview_path, params: { text: "before <script>alert(1)</script> vector<int> after" }
    assert_response :success
    assert_no_match %r{<script}, response.body
    assert_match %r{&lt;script&gt;alert\(1\)&lt;/script&gt; vector&lt;int&gt;}, response.body
  end

  test "blank text renders an empty fragment rather than erroring" do
    sign_in_as("admin", "admin")
    post markdown_preview_path
    assert_response :success
    assert_equal "", response.body.strip
  end

  test "a plain user is refused" do
    sign_in_as("jack", "jack")   # in no group
    post markdown_preview_path, params: { text: "x" }
    assert_response :redirect
  end

  test "an anonymous request is sent to login" do
    post markdown_preview_path, params: { text: "x" }
    assert_redirected_to login_main_path
  end

  # --- editor wiring on the forms ---

  def assert_editor_on(selector)
    assert_select "[data-controller='markdown-editor'][data-markdown-editor-preview-url-value=?]", markdown_preview_path do
      assert_select "textarea#{selector}[data-markdown-editor-target=source]"
    end
  end

  test "problem form mounts the editor on the viva briefing and the description" do
    sign_in_as("admin", "admin")
    get edit_problem_path(problems(:prob_viva))
    assert_response :success
    assert_editor_on "#problem_viva_prompt"
    assert_editor_on "#problem_description"
  end

  test "tag form mounts the editor on the LLM prompt of a viva_conduct tag" do
    sign_in_as("admin", "admin")
    tag = Tag.create!(name: "conduct", kind: :viva_conduct, params: "# Persona")
    get edit_tag_path(tag)
    assert_response :success
    assert_editor_on "#tag_params"
  end

  test "grounding material form mounts the editor on the body and keeps the draft target" do
    sign_in_as("admin", "admin")
    get edit_grounding_material_path(grounding_materials(:gm_dijkstra))
    assert_response :success
    assert_editor_on "#grounding_material_body"
    assert_select "textarea#grounding_material_body[data-grounding-draft-target=body]"
  end
end
