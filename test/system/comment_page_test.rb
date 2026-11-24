require "application_system_test_case"

# "View" on a submission comment opened in a new tab is a plain page load.
# There the AI-help header's inline highlight call runs before the
# highlight.js module has loaded, so it waits for the page; this checks the
# code really ends up highlighted.
class CommentPageTest < ApplicationSystemTestCase
  test "an AI-help answer opened as a page gets its code highlighted" do
    sub = submissions(:add1_by_john)
    c = sub.comments.create!(user: users(:john), kind: "llm_assist", status: "ok", llm_model: "m", cost: 10,
                             title: "Assistance by m", body: "```cpp\nint x = 1;\n```")
    login("john", "hello")
    visit submission_comment_path(sub, c)
    assert_selector "h2", text: "Comment: Assistance by m"
    assert_selector "pre code.hljs", wait: 5
  end

  test "the same answer clicked from the submission page still opens highlighted in the popup" do
    sub = submissions(:add1_by_john)
    sub.comments.create!(user: users(:john), kind: "llm_assist", status: "ok", llm_model: "m", cost: 10,
                         title: "Assistance by m", body: "```cpp\nint x = 1;\n```")
    login("john", "hello")
    visit submission_path(sub)
    within("#submission_comments") { click_on "View", wait: 10 }
    assert_selector ".modal.show pre code.hljs", wait: 5
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
