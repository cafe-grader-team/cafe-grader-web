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

  test "llm-kind tags force public to false" do
    %i[llm_prompt viva_conduct].each do |kind|
      tag = Tag.create!(name: "t-#{kind}", kind: kind, public: true)
      assert_equal false, tag.public, "#{kind} tag must not be public"
    end
  end

  test "normal tags keep their public flag" do
    tag = Tag.create!(name: 't-normal', kind: :normal, public: true)
    assert_equal true, tag.public
  end
end
