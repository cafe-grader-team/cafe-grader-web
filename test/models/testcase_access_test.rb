require 'test_helper'

# User#testcase_access (issues #18 and #59): the one predicate every testcase
# path reads. Group mode is on so the report set (editor mary, reporter reba)
# differs from the submit set (john, james); jack is in no group.
class TestcaseAccessTest < ActiveSupport::TestCase
  setup do
    set_grader_config('system.use_problem_group', 'true')
    set_grader_config('right.view_testcase', 'true')
    @prob = problems(:prob_add)
    @prob.update!(view_testcase: true)
  end

  teardown { reset_grader_config_cache }

  test 'admin is full whatever the flags say' do
    @prob.update!(view_testcase: false)
    set_grader_config('right.view_testcase', 'false')
    assert_equal :full, users(:admin).testcase_access(@prob)
  end

  test 'an editor and a reporter of the group are full, even with the problem flag off' do
    @prob.update!(view_testcase: false)
    assert_equal :full, users(:mary).testcase_access(@prob)
    assert_equal :full, users(:reba).testcase_access(@prob)
  end

  test 'a student of the group gets preview when both flags are on' do
    assert_equal :preview, users(:john).testcase_access(@prob)
    assert users(:john).can_view_testcase?(@prob)
  end

  test 'a student gets nothing when the problem flag is off, the site right is off, or they are outside the group' do
    @prob.update!(view_testcase: false)
    assert_nil users(:john).testcase_access(@prob)
    assert_not users(:john).can_view_testcase?(@prob)

    @prob.update!(view_testcase: true)
    set_grader_config('right.view_testcase', 'false')
    assert_nil users(:john).testcase_access(@prob)

    set_grader_config('right.view_testcase', 'true')
    assert_nil users(:jack).testcase_access(@prob)
  end

  test 'a disabled membership grants nothing' do
    groups_users(:john_in_group_a).update!(enabled: false)
    assert_nil users(:john).testcase_access(@prob)
  end

  test 'preview_of cuts at the limit, reports the size, and reads whole files at 0' do
    tc = testcases(:tc_add_1)
    tc.inp_file.attach(io: StringIO.new("0123456789\n"), filename: 'in.txt')
    assert_equal({ text: '0123', byte_size: 11, truncated: true }, Testcase.preview_of(tc.inp_file, 4))
    assert_equal({ text: "0123456789\n", byte_size: 11, truncated: false }, Testcase.preview_of(tc.inp_file, 0))
    assert_equal({ text: "0123456789\n", byte_size: 11, truncated: false }, Testcase.preview_of(tc.inp_file, 11))
    assert_equal({ text: '', byte_size: 0, truncated: false }, Testcase.preview_of(tc.ans_file, 4))
  end

  test 'the preview size comes from the config key and defaults to 2048 when the key is missing' do
    assert_equal 2048, GraderConfiguration.testcase_preview_bytes
    set_grader_config('ui.testcase_preview_bytes', '0')
    assert_equal 0, GraderConfiguration.testcase_preview_bytes
    GraderConfiguration.where(key: 'ui.testcase_preview_bytes').delete_all
    reset_grader_config_cache
    assert_equal 2048, GraderConfiguration.testcase_preview_bytes
  end
end
