require "test_helper"

class LanguagesControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # Admin happy-path tests
  # ============================================================

  test "admin can access languages index" do
    sign_in_as("admin", "admin")
    get languages_path
    assert_response :success
  end

  test "admin can access new language form" do
    sign_in_as("admin", "admin")
    get new_language_path
    assert_response :success
  end

  test "admin can create language" do
    sign_in_as("admin", "admin")
    assert_difference("Language.count") do
      post languages_path, params: { language: { name: "swift", pretty_name: "Swift", ext: "swift", common_ext: "swift" } }
    end
  end

  test "admin can edit language" do
    sign_in_as("admin", "admin")
    get edit_language_path(languages(:Language_c))
    assert_response :success
  end

  test "admin can update language" do
    sign_in_as("admin", "admin")
    patch language_path(languages(:Language_c)), params: { language: { pretty_name: "C Language" } }
    assert_redirected_to language_path(languages(:Language_c))
  end

  test "admin can destroy a non-system language" do
    sign_in_as("admin", "admin")
    lang = Language.create!(name: "temp", pretty_name: "Temp", ext: "tmp", common_ext: "tmp")
    assert_difference("Language.count", -1) do
      delete language_path(lang)
    end
  end

  # ============================================================
  # System-language read-only protection (already enforced)
  # ============================================================

  test "admin cannot update a system language (id < 20)" do
    sign_in_as("admin", "admin")
    sys_lang = Language.create!(id: 5, name: "syslang", pretty_name: "SysLang", ext: "sl", common_ext: "sl")
    patch language_path(sys_lang), params: { language: { pretty_name: "Hacked" } }
    assert_redirected_to languages_path
    assert_equal "SysLang", sys_lang.reload.pretty_name
  end

  test "admin cannot destroy a system language (id < 20)" do
    sign_in_as("admin", "admin")
    sys_lang = Language.create!(id: 6, name: "syslang2", pretty_name: "SysLang2", ext: "s2", common_ext: "s2")
    assert_no_difference("Language.count") do
      delete language_path(sys_lang)
    end
    assert_redirected_to languages_path
  end

  # ============================================================
  # Authorization tests
  # ============================================================

  test "unauthenticated user cannot list languages" do
    get languages_path
    assert_redirected_to login_main_path
  end

  test "unauthenticated user cannot create a language" do
    assert_no_difference("Language.count") do
      post languages_path, params: { language: { name: "evil", pretty_name: "Evil", ext: "ev", common_ext: "ev" } }
    end
    assert_redirected_to login_main_path
  end

  test "unauthenticated user cannot update a language" do
    patch language_path(languages(:Language_c)), params: { language: { pretty_name: "Pwned" } }
    assert_redirected_to login_main_path
    assert_equal "C", languages(:Language_c).reload.pretty_name
  end

  test "unauthenticated user cannot destroy a language" do
    lang = Language.create!(name: "victim", pretty_name: "Victim", ext: "v", common_ext: "v")
    assert_no_difference("Language.count") do
      delete language_path(lang)
    end
    assert_redirected_to login_main_path
  end

  test "normal user cannot create a language" do
    sign_in_as("john", "hello")
    assert_no_difference("Language.count") do
      post languages_path, params: { language: { name: "evil", pretty_name: "Evil", ext: "ev", common_ext: "ev" } }
    end
    assert_redirected_to list_main_path
  end

  test "group editor cannot create a language" do
    sign_in_as("mary", "mary")
    assert_no_difference("Language.count") do
      post languages_path, params: { language: { name: "evil", pretty_name: "Evil", ext: "ev", common_ext: "ev" } }
    end
    assert_redirected_to list_main_path
  end
end
