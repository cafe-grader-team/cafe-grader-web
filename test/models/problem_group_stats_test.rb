require "test_helper"

# Problem#group_stats_for and Problem#attempt_summary — the two grouped queries
# behind the stat page's "By group" card and its Solved/Attempted summary.
#
# Fixture shape: prob_add is in GroupA, whose enabled members are john and
# james (role user), admin and mary (editors) and reba (reporter). Fixture
# submissions on prob_add: one each by admin, john, james, all with nil points.
class ProblemGroupStatsTest < ActiveSupport::TestCase
  setup do
    @prob = problems(:prob_add)
    submissions(:add1_by_john).update_columns(points: 100)
    submissions(:add1_by_james).update_columns(points: 40)
  end

  def row_for(group, user = users(:admin))
    @prob.group_stats_for(user).find { |r| r.group == group }
  end

  test "one row per group: members, attempted, solved and mean best over attempted" do
    row = row_for(groups(:group_a))
    assert_equal 2, row.users        # john + james; editors/reporter are not members
    assert_equal 2, row.attempted
    assert_equal 1, row.solved       # john's 100
    assert_in_delta 70.0, row.mean_best, 0.01
  end

  test "editors' and reporters' submissions do not count toward the group" do
    # admin (editor of GroupA) submitted too; the row must not see it
    submissions(:add1_by_admin).update_columns(points: 100)
    row = row_for(groups(:group_a))
    assert_equal 2, row.attempted
    assert_equal 1, row.solved
  end

  test "best score per user, not per submission" do
    Submission.create!(user: users(:john), problem: @prob, language: languages(:Language_c),
                       source: "x", source_filename: "a.c", status: :done, submitted_at: Time.zone.now,
                       points: 20, number: 2)
    row = row_for(groups(:group_a))
    assert_equal 2, row.attempted
    assert_in_delta 70.0, row.mean_best, 0.01   # john still counts as 100
  end

  test "a user in two groups appears in both rows" do
    other = Group.create!(name: "Sec2", enabled: true)
    GroupProblem.create!(group: other, problem: @prob)
    GroupUser.create!(group: other, user: users(:john), role: :user)
    row = row_for(other)
    assert_equal 1, row.users
    assert_equal 1, row.attempted
    assert_equal 1, row.solved
    assert_equal 2, row_for(groups(:group_a)).attempted   # unchanged
  end

  test "disabled memberships are ignored" do
    groups_users(:john_in_group_a).update_columns(enabled: false)
    row = row_for(groups(:group_a))
    assert_equal 1, row.users
    assert_equal 1, row.attempted     # james only
    assert_in_delta 40.0, row.mean_best, 0.01
  end

  test "a group with members but no attempts has zero attempted and no mean" do
    other = Group.create!(name: "Fresh", enabled: true)
    GroupProblem.create!(group: other, problem: @prob)
    GroupUser.create!(group: other, user: users(:jack), role: :user)
    row = row_for(other)
    assert_equal 1, row.users
    assert_equal 0, row.attempted
    assert_equal 0, row.solved
    assert_nil row.mean_best
  end

  test "only groups the viewer may report on, and only groups the problem is in" do
    Group.create!(name: "Unrelated", enabled: true).then { |g| GroupUser.create!(group: g, user: users(:john), role: :user) }
    assert_equal [groups(:group_a)], @prob.group_stats_for(users(:admin)).map(&:group)
    assert_equal [groups(:group_a)], @prob.group_stats_for(users(:reba)).map(&:group)   # reporter of GroupA
    assert_empty @prob.group_stats_for(users(:jack))                                     # in no group
  end

  test "rows are ordered by group name" do
    z = Group.create!(name: "Zed", enabled: true); GroupProblem.create!(group: z, problem: @prob)
    a = Group.create!(name: "Alpha", enabled: true); GroupProblem.create!(group: a, problem: @prob)
    assert_equal %w[Alpha GroupA Zed], @prob.group_stats_for(users(:admin)).map { |r| r.group.name }
  end

  test "attempt_summary counts distinct users over every regular submission" do
    Submission.create!(user: users(:john), problem: @prob, language: languages(:Language_c),
                       source: "x", source_filename: "a.c", status: :done, submitted_at: Time.zone.now,
                       points: 20, number: 2)
    assert_equal({ attempted: 3, solved: 1 }, @prob.attempt_summary)   # admin, john, james; john solved
  end

  test "attempt_summary ignores shadow (repaired) submissions" do
    shadow = Submission.create!(user: users(:jack), problem: @prob, language: languages(:Language_c),
                                source: "x", source_filename: "a.c", status: :done, submitted_at: Time.zone.now,
                                points: 100, number: 1, repaired_from_id: submissions(:add1_by_john).id)
    assert shadow.persisted?
    assert_equal({ attempted: 3, solved: 1 }, @prob.attempt_summary)
  end
end
