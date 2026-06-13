require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "tag fixtures are valid" do
    assert tags(:tag_easy).persisted?
    assert tags(:tag_hard).persisted?
  end

  test "tags have problems through problem_tags" do
    tag = tags(:tag_easy)
    assert_includes tag.problems, problems(:prob_add)
  end
end
