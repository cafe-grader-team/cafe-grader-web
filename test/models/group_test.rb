require "test_helper"

class GroupTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid group fixture" do
    assert groups(:group_a).valid?
  end

  test "name must be present" do
    group = Group.new(description: "test")
    assert_not group.valid?
    assert group.errors[:name].any?
  end

  test "name must be unique" do
    group = Group.new(name: "Group A")
    assert_not group.valid?
    assert group.errors[:name].any?
  end

  test "name must match format" do
    group = Group.new(name: "bad name!")
    assert_not group.valid?
    assert group.errors[:name].any?
  end

  # --- Scopes ---

  test "enabled scope" do
    enabled = Group.enabled
    assert_includes enabled, groups(:group_a)
    assert_not_includes enabled, groups(:group_b)
  end

  test "editable_by_user returns groups where user is editor" do
    # admin is editor in group_a
    groups = Group.editable_by_user(users(:admin).id)
    assert_includes groups, groups(:group_a)
  end

  test "editable_by_user excludes groups where user is not editor" do
    # john is user (role 0) in group_a, not editor
    groups = Group.editable_by_user(users(:john).id)
    assert_not_includes groups, groups(:group_a)
  end

  test "submittable_by_user returns groups where user is member" do
    groups = Group.submittable_by_user(users(:john).id)
    assert_includes groups, groups(:group_a)
  end

  test "reportable_by_user returns groups where user is editor or reporter" do
    # mary is editor in group_a
    groups = Group.reportable_by_user(users(:mary).id)
    assert_includes groups, groups(:group_a)
  end

  # --- Methods ---

  test "add_users_skip_existing adds new users" do
    group = groups(:group_a)
    mary = users(:mary)
    # mary is already in group_a as editor
    disabled = users(:disabled_user)
    result = group.add_users_skip_existing(User.where(id: [disabled.id]))
    assert_match(/changed/i, result[:title])
  end

  test "add_users_skip_existing with all existing returns unchanged" do
    group = groups(:group_a)
    result = group.add_users_skip_existing(User.where(id: [users(:john).id]))
    assert_match(/NOT changed/i, result[:title])
  end

  # --- Associations ---

  test "group has users and problems" do
    group = groups(:group_a)
    assert_includes group.users, users(:john)
    assert_includes group.problems, problems(:prob_add)
  end
end
