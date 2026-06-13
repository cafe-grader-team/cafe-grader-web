require "test_helper"

class LanguageTest < ActiveSupport::TestCase
  test "default_submission_filename returns correct name" do
    lang = languages(:Language_c)
    assert_equal "submission.c", lang.default_submission_filename
  end

  test "find_by_extension finds known extension" do
    lang = Language.find_by_extension("cpp")
    assert_not_nil lang
    assert_equal "cpp", lang.name
  end

  test "find_by_extension returns nil for unknown extension" do
    lang = Language.find_by_extension("xyz123")
    assert_nil lang
  end

  test "cache_ext_hash populates extension cache" do
    Language.cache_ext_hash
    lang = Language.find_by_extension("c")
    assert_not_nil lang
    assert_equal "c", lang.name
  end
end
