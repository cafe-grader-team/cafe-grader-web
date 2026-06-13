require "test_helper"

# Covers SubmissionsController#set_language for the NEW-submission page
# (direct_edit_problem): which submission UI is rendered — the binary FILE
# UPLOAD form or the CODE EDITOR — across the (problem permitted languages) x
# (user default language) matrix.
#
# The 18 nominal matrix cells collapse into a handful of behavioral equivalence
# classes, because one rule drives everything:
#
#   @language = user default (only if it is in the permitted set)
#               else lowest-id permitted language
#   @as_binary = @language.binary?      # true -> UPLOAD, false -> EDITOR
#
# So we test the distinct branches, not every redundant cell:
#   - forced (exactly one permitted lang): binary vs source, default ignored
#   - not forced, default IS permitted:    binary vs source default honored
#   - not forced, default NOT permitted:   default ignored, deterministic fallback
#   - not forced, no default:              deterministic fallback (incl. blank=all)
#   - stale/empty permitted set:           guard, must not crash
#
# The test fixtures ship only source languages, so we create binary languages at
# runtime. They get the highest auto-increment ids, which mirrors production
# (where the sole binary lang, `archive`, sorts last by id) — this is exactly
# why a mixed/blank set with no default lands on a *source* language (editor).
class SubmissionLanguageSelectionTest < ActionDispatch::IntegrationTest
  setup do
    @archive  = Language.find_or_create_by!(name: "archive")  { |l| l.pretty_name = "Archive";   l.binary = true; l.ext = "zip" }
    @archive2 = Language.find_or_create_by!(name: "archive2") { |l| l.pretty_name = "Archive 2"; l.binary = true; l.ext = "tar" }
    @c       = languages(:Language_c)
    @cpp     = languages(:Language_cpp)
    @problem = problems(:prob_add)   # available, has a live dataset, viewable by john
  end

  # Open the NEW-submission page as john, after pinning the problem's permitted
  # languages and john's default language.
  def open_new_submission(permitted_lang:, default:)
    @problem.update!(permitted_lang: permitted_lang)
    users(:john).update!(default_language: default)
    sign_in_as("john", "hello")
    get direct_edit_problem_submissions_path(problem_id: @problem.id)
    assert_response :success
  end

  def assert_upload_mode
    assert_match(/accepts only a binary file upload/i, response.body, "expected BINARY UPLOAD mode")
    assert_select "div#editor", false, "code editor must NOT render in upload mode"
  end

  def assert_editor_mode
    assert_select "div#editor", true, "expected CODE EDITOR mode"
    assert_no_match(/accepts only a binary file upload/i, response.body, "upload notice must NOT render in editor mode")
  end

  def assert_selected_language(lang)
    assert_select %(select#language_id option[selected][value="#{lang.id}"]), true,
                  "expected #{lang.name} (id #{lang.id}) to be preselected"
  end

  def assert_locked(locked)
    assert_select "select#language_id[disabled]", locked,
                  locked ? "language dropdown should be locked" : "language dropdown should be selectable"
  end

  # --- Forced: exactly one permitted language (user default is irrelevant) ---

  test "single permitted source language: editor, locked, default ignored" do
    # default is binary, but a single-permitted problem ignores it
    open_new_submission(permitted_lang: @cpp.name, default: @archive)
    assert_editor_mode
    assert_selected_language @cpp
    assert_locked true
  end

  test "single permitted binary language: upload, locked, default ignored" do
    # default is source, but a single-permitted problem ignores it
    open_new_submission(permitted_lang: @archive.name, default: @cpp)
    assert_upload_mode
    assert_selected_language @archive
    assert_locked true
  end

  # --- Not forced, user default IS in the permitted set (default is honored) ---

  test "multi permitted, default is a permitted source language: editor on the default" do
    open_new_submission(permitted_lang: "#{@c.name} #{@cpp.name}", default: @cpp)
    assert_editor_mode
    assert_selected_language @cpp
    assert_locked false
  end

  test "mixed permitted, default is the permitted binary language: upload on the default" do
    open_new_submission(permitted_lang: "#{@cpp.name} #{@archive.name}", default: @archive)
    assert_upload_mode
    assert_selected_language @archive
    assert_locked false
  end

  # --- Not forced, user default NOT in the permitted set (ignored -> fallback) ---

  test "binary default not permitted (source-only set): ignored, editor on lowest-id permitted" do
    open_new_submission(permitted_lang: "#{@c.name} #{@cpp.name}", default: @archive)
    assert_editor_mode
    assert_selected_language [@c, @cpp].min_by(&:id)
    assert_locked false
  end

  test "source default not permitted (binary-only set, >=2): ignored, upload on lowest-id permitted" do
    open_new_submission(permitted_lang: "#{@archive.name} #{@archive2.name}", default: @cpp)
    assert_upload_mode
    assert_selected_language [@archive, @archive2].min_by(&:id)
    assert_locked false
  end

  # --- Not forced, no user default (deterministic fallback) ---

  test "blank permitted set, no default: editor on lowest-id language (NOT binary upload)" do
    open_new_submission(permitted_lang: "", default: nil)
    assert_editor_mode
    assert_locked false
    assert_selected_language Language.all.to_a.min_by(&:id)
  end

  test "mixed permitted set, no default: editor on lowest-id permitted (source)" do
    open_new_submission(permitted_lang: "#{@cpp.name} #{@archive.name}", default: nil)
    assert_editor_mode
    assert_selected_language [@cpp, @archive].min_by(&:id)
    assert_locked false
  end

  # --- Guard: stale permitted_lang naming only unknown languages ---

  test "permitted set of only-unknown language names does not crash" do
    # get_permitted_lang_as_ids => [], permitted.first => nil; the guard falls
    # back to Language.first instead of raising on Language.find(nil).
    open_new_submission(permitted_lang: "no_such_lang another_missing", default: nil)
    assert_response :success
  end

  # --- Editing an existing submission preserves its own (historical) language ---

  test "editing a submission honors its stored language even when no longer permitted" do
    sub = submissions(:add1_by_admin)             # admin's own submission on prob_add
    sub.update_columns(language_id: @archive.id)  # stored language is binary; bypass the coercion callback
    @problem.update!(permitted_lang: "#{@c.name} #{@cpp.name}")  # restrict to a source-only set (excludes archive)
    sign_in_as("admin", "admin")
    get edit_submission_path(sub)
    assert_response :success
    assert_upload_mode   # set_language honored @submission.language (binary), not the permitted-set fallback
  end

  # --- Submit-time guard: the permitted set is enforced server-side ---

  test "submit rejects a language_id outside the permitted set" do
    @problem.update!(permitted_lang: "#{@c.name} #{@cpp.name}")  # source-only, more than one permitted
    sign_in_as("admin", "admin")
    assert_no_difference "Submission.count" do
      post submit_main_path, params: {
        submission: { problem_id: @problem.id },
        language_id: @archive.id,                                # not permitted
        editor_text: "print(1)"
      }
    end
    assert_redirected_to list_main_path
    assert_match(/not permitted/i, flash[:alert])
  end

  test "submit accepts a language_id within the permitted set" do
    @problem.update!(permitted_lang: "#{@c.name} #{@cpp.name}")
    sign_in_as("admin", "admin")
    assert_difference "Submission.count", 1 do
      post submit_main_path, params: {
        submission: { problem_id: @problem.id },
        language_id: @cpp.id,                                    # permitted
        editor_text: "int main() { return 0; }"
      }
    end
    assert_redirected_to edit_submission_path(Submission.last)
  end
end
