# test/models/test_drive_exclusion_test.rb
require 'test_helper'

# Mirrors shadow_exclusion_test.rb for viva test-drives (submissions.test_drive):
# an author's trial run must vanish from every student-facing count, score,
# quota and report, while staying visible to its author and to staff.
# Design: docs/superpowers/specs/2026-09-23-viva-test-drive-design.md
class TestDriveExclusionTest < ActiveSupport::TestCase
  def viva_language
    Language.find_or_create_by!(name: "viva") { |l| l.pretty_name = "Viva Exam" }
  end

  setup do
    # Group mode on, and the viva problem placed in group_a, so that mary
    # (editor of group_a) is an editor of the problem and john (member) is
    # one of its students. Fixtures keep prob_viva out of every group.
    set_grader_config('system.use_problem_group', 'true')
    @problem = problems(:prob_viva)
    GroupProblem.create!(group: groups(:group_a), problem: @problem, enabled: true)
    @mary = users(:mary)
    @john = users(:john)

    @drive = Submission.create!(user: @mary, problem: @problem, language: viva_language,
                                status: :done, submitted_at: Time.zone.now, points: 100,
                                test_drive: true)
    @drive.viva_turns.create!(role: :assistant, status: :ok, content: 'Q1?', cost: 0.5)
    @drive.viva_turns.create!(role: :student,   status: :ok, content: 'A1')

    @real = Submission.create!(user: @john, problem: @problem, language: viva_language,
                               status: :done, submitted_at: Time.zone.now, points: 40)
    @real.viva_turns.create!(role: :assistant, status: :ok, content: 'Q1?', cost: 0.5)
    @real.viva_turns.create!(role: :student,   status: :ok, content: 'A1')
  end

  test "regular excludes test-drives; test_drives finds them; shadows stay separate" do
    refute_includes Submission.regular, @drive
    assert_includes Submission.regular, @real
    assert_includes Submission.test_drives, @drive
    refute_includes Submission.test_drives, @real
    refute_includes Submission.shadow, @drive, "a test-drive is not a near-miss shadow"
  end

  test "author, admin and reporter can view a test-drive; a peer cannot, even with transcript sharing on" do
    set_grader_config('right.user_view_submission', 'true')
    @problem.update!(view_submission: true)
    assert @john.can_view_submission?(@real), "sanity: john sees his own real session"
    assert @mary.can_view_submission?(@real), "sanity: the editor sees a student's session"

    assert @mary.can_view_submission?(@drive),         "author sees their own test-drive"
    assert users(:admin).can_view_submission?(@drive), "admin sees every test-drive"
    assert users(:reba).can_view_submission?(@drive),  "reporter of the group sees it"
    refute @john.can_view_submission?(@drive),         "a peer must not, even when the problem shares transcripts"
  end

  test "problem stats exclude test-drives" do
    # Problem#get_submission_stat already reads Submission.regular; exercised
    # here as a downstream consumer of the widened scope.
    regular_count = Submission.regular.where(problem_id: @problem.id).count
    stats = @problem.get_submission_stat
    assert_equal regular_count, stats[:total_sub]
    assert_equal 0, stats[:pass], "the test-drive's 100 points must not count as a pass"
  end

  test "problem_stat recompute excludes test-drives" do
    regular_count = Submission.regular.where(problem_id: @problem.id).count
    ProblemStat.recompute_all
    assert_equal regular_count, ProblemStat.find_by(problem_id: @problem.id).sub_count
  end

  test "contest submissions and the AI-usage report exclude test-drives" do
    contest = Contest.create!(name: 'td-test', enabled: true, start: 1.hour.ago, stop: 1.hour.from_now)
    contest.contests_users.create!(user: @mary, enabled: true)
    contest.contests_users.create!(user: @john, enabled: true)
    contest.problems << @problem
    assert_includes contest.submissions, @real
    refute_includes contest.submissions, @drive

    report = AiUsageReport.new(contest)
    assert_equal 1, report.summary[:sessions_opened], "john's real interview counts, mary's test-drive does not"
    assert_equal 1, report.summary[:turns],           "only the real session's LLM call is counted"
  end
end
