require "test_helper"

# 3b authorization model: an EDITOR is a group-scoped content curator that sees
# every problem in their group regardless of Problem#available / Group#enabled;
# a REPORTER stays gated to live content (available problems in an enabled
# group). Editor visibility is always a superset of reporter visibility.
#
# Fixture layout (group_a is enabled):
#   prob_add  -> group_a, available: true
#   prob_sub  -> group_a, available: false
#   mary      -> editor  of group_a
#   reba      -> reporter of group_a
class ProblemScopeAuthorizationTest < ActiveSupport::TestCase
  setup do
    @editor   = users(:mary)
    @reporter = users(:reba)
    @group    = groups(:group_a)
    @available   = problems(:prob_add)   # available: true,  in group_a
    @unavailable = problems(:prob_sub)   # available: false, in group_a
  end

  # --- editor: curator, bypasses available + group.enabled ---

  test "editor scope includes an unavailable problem in their group" do
    ids = Problem.group_editable_by_user(@editor.id).ids
    assert_includes ids, @available.id
    assert_includes ids, @unavailable.id,
      "an editor should be able to manage a draft/archived (unavailable) problem in their group"
  end

  test "editor scope still includes problems when the group is disabled" do
    @group.update!(enabled: false)
    ids = Problem.group_editable_by_user(@editor.id).ids
    assert_includes ids, @available.id
    assert_includes ids, @unavailable.id,
      "disabling (archiving) a group must not lock its editor out"
  end

  # --- reporter: gated by available + group.enabled ---

  test "reporter scope excludes unavailable problems" do
    ids = Problem.group_reportable_by_user(@reporter.id).ids
    assert_includes ids, @available.id
    refute_includes ids, @unavailable.id, "a reporter must not see unavailable problems"
  end

  test "reporter scope is empty when the group is disabled" do
    @group.update!(enabled: false)
    assert_empty Problem.group_reportable_by_user(@reporter.id).ids,
      "a reporter must not see an archived (disabled) group"
  end

  # --- invariant: editor's report visibility >= reporter's ---

  test "an editor's report scope is a strict superset of a reporter's" do
    editor_report   = Problem.group_reportable_by_user(@editor.id).ids
    reporter_report = Problem.group_reportable_by_user(@reporter.id).ids
    assert (reporter_report - editor_report).empty?,
      "everything a reporter can report on, an editor can too"
    assert_includes editor_report, @unavailable.id,
      "the editor additionally reports on archived/unavailable content"
    refute_includes reporter_report, @unavailable.id
  end

  # --- content predicates flow from the scopes (need group mode) ---

  test "editor can edit and view an unavailable problem; reporter cannot" do
    set_grader_config("system.use_problem_group", true)

    assert @editor.can_edit_problem?(@unavailable), "editor edits their own unavailable problem"
    assert @editor.can_view_problem?(@unavailable)
    assert @editor.can_report_problem?(@unavailable)

    refute @reporter.can_report_problem?(@unavailable), "reporter cannot report an unavailable problem"
    refute @reporter.can_view_problem?(@unavailable)
    refute @reporter.can_edit_problem?(@unavailable),   "a reporter can never edit"
  end

  # --- Group.reportable_by_user: the group-level counterpart, keeps the report
  #     gate / dropdowns / reportable_users role-aware ---

  test "reportable groups include an archived group for its editor" do
    @group.update!(enabled: false)
    assert_includes Group.reportable_by_user(@editor.id).ids, @group.id,
      "an editor can still report on their archived group"
  end

  test "reportable groups exclude an archived group for a reporter" do
    assert_includes Group.reportable_by_user(@reporter.id).ids, @group.id  # enabled -> visible
    @group.update!(enabled: false)
    refute_includes Group.reportable_by_user(@reporter.id).ids, @group.id,
      "a reporter must not see an archived group (it would be a dead-end filter)"
  end
end
