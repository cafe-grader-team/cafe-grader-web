require "test_helper"

class UserAuthorizationTest < ActiveSupport::TestCase
  # =============================================================
  # Test fixture summary for reference:
  #
  # Users:  john (normal), admin, mary (group editor + contest editor),
  #         james (contest_a user), jack (contest_a + contest_b user),
  #         disabled_user (not activated, disabled in contest_a)
  #
  # Groups: group_a (enabled) has: john(user), admin(editor), mary(editor), james(user)
  #         group_b (disabled)
  #
  # Group problems: prob_add + prob_sub in group_a (both enabled)
  #
  # Contests: contest_a (enabled, active now), contest_b (enabled, active now),
  #           contest_c (disabled, ended)
  #
  # Contest users: james(user in a), jack(user in a+b), mary(editor in a),
  #                admin(editor in a), disabled_user(disabled in a)
  #
  # Contest problems: prob_add + easy in contest_a; easy + hard in contest_b
  #
  # Problems: prob_add (available), prob_sub (unavailable), easy (available), hard (available)
  # =============================================================

  # -------------------------------------------------------
  # SECTION 1: problems_for_action in STANDARD MODE (no groups)
  # -------------------------------------------------------

  test "standard no-group: normal user can submit to available problems only" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    john = users(:john)

    submittable = john.problems_for_action(:submit)
    assert_includes submittable, problems(:prob_add)
    assert_includes submittable, problems(:easy)
    assert_not_includes submittable, problems(:prob_sub)  # not available
  end

  test "standard no-group: normal user cannot edit or report any problem" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    john = users(:john)

    assert_empty john.problems_for_action(:edit)
    assert_empty john.problems_for_action(:report)
  end

  test "standard no-group: admin gets all problems regardless" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")

    assert_equal Problem.count, users(:admin).problems_for_action(:submit).count
    assert_equal Problem.count, users(:admin).problems_for_action(:edit).count
    assert_equal Problem.count, users(:admin).problems_for_action(:report).count
  end

  test "standard no-group: disabled user gets no problems" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    user = users(:disabled_user)
    user.update_columns(enabled: false)

    assert_empty user.problems_for_action(:submit)
  end

  # -------------------------------------------------------
  # SECTION 2: problems_for_action in STANDARD MODE (with groups)
  # -------------------------------------------------------

  test "standard group: user sees only available+enabled problems in their groups" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    john = users(:john)  # user role in group_a

    submittable = john.problems_for_action(:submit)
    # prob_add is available + enabled in group_a
    assert_includes submittable, problems(:prob_add)
    # prob_sub is NOT available, so excluded from submit
    assert_not_includes submittable, problems(:prob_sub)
    # easy is not in group_a
    assert_not_includes submittable, problems(:easy)
  end

  test "standard group: user(role=0) cannot edit or report" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    john = users(:john)  # role=0 (user) in group_a

    assert_empty john.problems_for_action(:edit)
    assert_empty john.problems_for_action(:report)
  end

  test "standard group: editor can edit problems in their group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    mary = users(:mary)  # editor in group_a

    editable = mary.problems_for_action(:edit)
    assert_includes editable, problems(:prob_add)
  end

  test "standard group: editor can report problems in their group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    mary = users(:mary)

    reportable = mary.problems_for_action(:report)
    assert_includes reportable, problems(:prob_add)
  end

  test "standard group: user not in any group gets nothing" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    # disabled_user is not in any group
    user = users(:disabled_user)
    user.update_columns(enabled: true, activated: true)

    assert_empty user.problems_for_action(:submit)
  end

  test "standard group: disabled group hides its problems" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    # group_b is disabled, even if we added john to it
    GroupUser.create!(group: groups(:group_b), user: users(:john), role: :user)
    GroupProblem.create!(group: groups(:group_b), problem: problems(:easy))

    submittable = users(:john).problems_for_action(:submit)
    # easy is in group_b (disabled), so should not appear via group_b
    assert_not_includes submittable, problems(:easy)
  end

  # -------------------------------------------------------
  # SECTION 3: problems_for_action in CONTEST MODE
  # -------------------------------------------------------

  test "contest mode: user sees only problems in their active contests" do
    set_grader_config("system.mode", "contest")
    james = users(:james)  # in contest_a only

    submittable = james.problems_for_action(:submit)
    # contest_a has prob_add and easy
    assert_includes submittable, problems(:prob_add)
    assert_includes submittable, problems(:easy)
    # hard is only in contest_b, james is not in contest_b
    assert_not_includes submittable, problems(:hard)
  end

  test "contest mode: user in multiple contests sees union of problems" do
    set_grader_config("system.mode", "contest")
    jack = users(:jack)  # in contest_a and contest_b

    submittable = jack.problems_for_action(:submit)
    assert_includes submittable, problems(:prob_add)  # contest_a
    assert_includes submittable, problems(:easy)      # both contests
    assert_includes submittable, problems(:hard)      # contest_b
  end

  test "contest mode: user not in any contest sees nothing" do
    set_grader_config("system.mode", "contest")
    john = users(:john)  # not in any contest

    assert_empty john.problems_for_action(:submit)
  end

  test "contest mode: disabled contest user sees nothing" do
    set_grader_config("system.mode", "contest")
    user = users(:disabled_user)  # disabled in contest_a
    user.update_columns(enabled: true, activated: true)

    assert_empty user.problems_for_action(:submit)
  end

  test "contest mode: normal user cannot edit/report contest problems" do
    set_grader_config("system.mode", "contest")
    james = users(:james)  # user role in contest_a

    assert_empty james.problems_for_action(:edit)
    assert_empty james.problems_for_action(:report)
  end

  test "contest mode: contest editor can edit/report contest problems" do
    set_grader_config("system.mode", "contest")
    mary = users(:mary)  # editor in contest_a

    editable = mary.problems_for_action(:edit)
    assert_includes editable, problems(:prob_add)
    assert_includes editable, problems(:easy)
  end

  test "contest mode: ended contest hides problems" do
    set_grader_config("system.mode", "contest")
    # Add john to contest_c (ended)
    ContestUser.create!(contest: contests(:contest_c), user: users(:john), role: :user, enabled: true)
    ContestProblem.create!(contest: contests(:contest_c), problem: problems(:hard), number: 1, enabled: true)

    assert_empty users(:john).problems_for_action(:submit)
  end

  test "contest mode: admin still sees all problems" do
    set_grader_config("system.mode", "contest")
    assert_equal Problem.count, users(:admin).problems_for_action(:submit).count
  end

  # -------------------------------------------------------
  # SECTION 4: can_view_problem?
  # -------------------------------------------------------

  test "can_view_problem: admin can view any problem in any mode" do
    [["standard", "false"], ["standard", "true"], ["contest", "false"]].each do |mode, group|
      set_grader_config("system.mode", mode)
      set_grader_config("system.use_problem_group", group)

      assert users(:admin).can_view_problem?(problems(:prob_add))
      assert users(:admin).can_view_problem?(problems(:prob_sub))
    end
  end

  test "can_view_problem: normal user cannot view unavailable problem in standard no-group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")

    assert_not users(:john).can_view_problem?(problems(:prob_sub))
  end

  test "can_view_problem: group editor can view unavailable problem in their group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    mary = users(:mary)  # editor in group_a, prob_sub is in group_a

    # editors have report access which covers unavailable problems
    assert mary.can_view_problem?(problems(:prob_add))
  end

  test "can_view_problem: contest user can view contest problem during contest" do
    set_grader_config("system.mode", "contest")
    james = users(:james)

    assert james.can_view_problem?(problems(:prob_add))  # in contest_a
    assert_not james.can_view_problem?(problems(:hard))   # only in contest_b
  end

  test "can_view_problem: contest user cannot view problem outside their contest" do
    set_grader_config("system.mode", "contest")
    james = users(:james)  # only in contest_a

    # prob_sub is not in any contest
    assert_not james.can_view_problem?(problems(:prob_sub))
    # hard is only in contest_b
    assert_not james.can_view_problem?(problems(:hard))
  end

  # -------------------------------------------------------
  # SECTION 5: can_view_submission? (EXAM CRITICAL)
  # -------------------------------------------------------

  test "can_view_submission: admin can always view any submission" do
    set_grader_config("system.mode", "contest")
    set_grader_config("right.user_view_submission", "false")

    assert users(:admin).can_view_submission?(submissions(:add1_by_john))
    assert users(:admin).can_view_submission?(submissions(:add1_by_james))
  end

  test "can_view_submission: user can view own submission in standard mode" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.user_view_submission", "false")

    john = users(:john)
    assert john.can_view_submission?(submissions(:add1_by_john))
  end

  test "can_view_submission: user CANNOT view other's submission when config is off" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.user_view_submission", "false")

    john = users(:john)
    assert_not john.can_view_submission?(submissions(:add1_by_admin))
  end

  test "can_view_submission: user CAN view other's submission when config is on" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.user_view_submission", "true")

    john = users(:john)
    assert john.can_view_submission?(submissions(:add1_by_admin))
  end

  test "can_view_submission: contest user can view own submission during contest" do
    set_grader_config("system.mode", "contest")
    set_grader_config("right.user_view_submission", "false")

    james = users(:james)
    assert james.can_view_submission?(submissions(:add1_by_james))
  end

  test "can_view_submission: contest user CANNOT view other's submission in exam" do
    set_grader_config("system.mode", "contest")
    set_grader_config("right.user_view_submission", "false")

    james = users(:james)
    # james should NOT be able to see admin's submission even for same problem
    assert_not james.can_view_submission?(submissions(:add1_by_admin))
  end

  test "can_view_submission: user cannot view submission for problem they have no access to" do
    set_grader_config("system.mode", "contest")
    set_grader_config("right.user_view_submission", "false")

    james = users(:james)  # in contest_a
    # sub1_by_admin is for prob_sub, which is NOT in contest_a
    assert_not james.can_view_submission?(submissions(:sub1_by_admin))
  end

  test "can_view_submission: group reporter can view any submission for their problems" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    set_grader_config("right.user_view_submission", "false")

    mary = users(:mary)  # editor(=reporter+) in group_a
    # mary should be able to view john's submission for prob_add (in group_a)
    assert mary.can_view_submission?(submissions(:add1_by_john))
  end

  # -------------------------------------------------------
  # SECTION 6: can_view_testcase? (prevents data leakage)
  # -------------------------------------------------------

  test "can_view_testcase: blocked when config is off" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.view_testcase", "false")

    assert_not users(:john).can_view_testcase?(problems(:prob_add))
  end

  test "can_view_testcase: allowed when config is on AND user can view problem" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    set_grader_config("right.view_testcase", "true")

    assert users(:john).can_view_testcase?(problems(:prob_add))
  end

  test "can_view_testcase: blocked even with config on if user cannot view problem" do
    set_grader_config("system.mode", "contest")
    set_grader_config("right.view_testcase", "true")

    john = users(:john)  # not in any contest
    assert_not john.can_view_testcase?(problems(:prob_add))
  end

  test "can_view_testcase: admin always allowed regardless of config" do
    set_grader_config("right.view_testcase", "false")
    assert users(:admin).can_view_testcase?(problems(:prob_add))
  end

  # -------------------------------------------------------
  # SECTION 7: can_edit_problem?
  # -------------------------------------------------------

  test "can_edit_problem: admin can always edit" do
    assert users(:admin).can_edit_problem?(problems(:prob_add))
  end

  test "can_edit_problem: normal user cannot edit in standard no-group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    assert_not users(:john).can_edit_problem?(problems(:prob_add))
  end

  test "can_edit_problem: group editor can edit in group mode" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    assert users(:mary).can_edit_problem?(problems(:prob_add))
  end

  test "can_edit_problem: group user(role=0) cannot edit even in group mode" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    assert_not users(:john).can_edit_problem?(problems(:prob_add))
  end

  # -------------------------------------------------------
  # SECTION 8: can_report_problem?
  # -------------------------------------------------------

  test "can_report_problem: admin can always report" do
    assert users(:admin).can_report_problem?(problems(:prob_add))
    assert users(:admin).can_report_problem?(problems(:prob_sub))
  end

  test "can_report_problem: normal user cannot report in standard no-group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "false")
    assert_not users(:john).can_report_problem?(problems(:prob_add))
  end

  test "can_report_problem: group editor can report problems in their group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    assert users(:mary).can_report_problem?(problems(:prob_add))
  end

  test "can_report_problem: group user cannot report even in their group" do
    set_grader_config("system.mode", "standard")
    set_grader_config("system.use_problem_group", "true")
    assert_not users(:john).can_report_problem?(problems(:prob_add))
  end

  test "can_report_problem: contest editor can report contest problems" do
    set_grader_config("system.mode", "contest")
    mary = users(:mary)  # editor in contest_a
    assert mary.can_report_problem?(problems(:prob_add))
  end

  test "can_report_problem: contest user cannot report" do
    set_grader_config("system.mode", "contest")
    assert_not users(:james).can_report_problem?(problems(:prob_add))
  end

  # -------------------------------------------------------
  # SECTION 9: set_exam_mode lockdown
  # -------------------------------------------------------

  test "set_exam_mode disables all permissive configs" do
    GraderConfiguration.set_exam_mode(true)
    reset_grader_config_cache

    assert_not GraderConfiguration["right.bypass_agreement"]
    assert_not GraderConfiguration["right.multiple_ip_login"]
    assert_not GraderConfiguration["right.user_hall_of_fame"]
    assert_not GraderConfiguration["right.user_view_submission"]
    assert_not GraderConfiguration["right.view_testcase"]
  end

  test "set_exam_mode resets all user device locks" do
    users(:john).update_columns(last_ip: "some-uuid")
    GraderConfiguration.set_exam_mode(true)
    # set_exam_mode does User.update_all(last_ip: false) which clears the UUID
    assert_not_equal "some-uuid", users(:john).reload.last_ip
  end

  # -------------------------------------------------------
  # SECTION 9: disabled user / enabled flag
  # -------------------------------------------------------

  test "disabled user (enabled=false) gets no problems in any mode" do
    user = users(:john)
    user.update_columns(enabled: false)

    ["standard", "contest"].each do |mode|
      set_grader_config("system.mode", mode)
      assert_empty user.problems_for_action(:submit),
        "disabled user should get no problems in #{mode} mode"
    end
  end

  test "deactivated user cannot authenticate" do
    assert_nil User.authenticate("disabled", "disabled")
  end
end
