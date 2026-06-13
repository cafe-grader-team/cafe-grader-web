require "test_helper"

class ProblemTagTest < ActiveSupport::TestCase
  test "problem_tag fixture links problem and tag" do
    pt = problem_tags(:add_easy)
    assert_equal problems(:prob_add), pt.problem
    assert_equal tags(:tag_easy), pt.tag
  end
end
