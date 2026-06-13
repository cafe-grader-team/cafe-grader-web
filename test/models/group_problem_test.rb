require "test_helper"

class GroupProblemTest < ActiveSupport::TestCase
  test "uniqueness of problem in group" do
    # prob_add is already in group_a
    gp = GroupProblem.new(group: groups(:group_a), problem: problems(:prob_add))
    assert_not gp.valid?
  end

  test "allows same problem in different groups" do
    gp = GroupProblem.new(group: groups(:group_b), problem: problems(:prob_add))
    assert gp.valid?
  end

  test "belongs to group and problem" do
    gp = GroupProblem.where(group: groups(:group_a), problem: problems(:prob_add)).first
    assert_equal groups(:group_a), gp.group
    assert_equal problems(:prob_add), gp.problem
  end
end
