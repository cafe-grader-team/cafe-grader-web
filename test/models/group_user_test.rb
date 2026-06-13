require "test_helper"

class GroupUserTest < ActiveSupport::TestCase
  test "role enum values" do
    gu = GroupUser.new(group: groups(:group_a), user: users(:john), role: :user)
    assert gu.user?

    gu.role = :editor
    assert gu.editor?

    gu.role = :reporter
    assert gu.reporter?
  end

  test "uniqueness of user in group" do
    # john is already in group_a
    gu = GroupUser.new(group: groups(:group_a), user: users(:john))
    assert_not gu.valid?
  end

  test "allows same user in different groups" do
    gu = GroupUser.new(group: groups(:group_b), user: users(:john))
    assert gu.valid?
  end
end
