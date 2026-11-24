require "test_helper"

class Viva::StartPolicyTest < ActiveSupport::TestCase
  setup do
    @problem = problems(:prob_viva)
    @john    = users(:john)
    @lang    = Language.find_or_create_by!(name: 'viva') { |l| l.pretty_name = 'Viva Exam' }
  end

  # A viva session saved without the submit-permission check, so the same
  # helper works in contest mode.
  def session_for(user = @john, answered: true, submitted_at: Time.zone.now, **attrs)
    s = Submission.new(user: user, problem: @problem, language: @lang, status: :submitted,
                       submitted_at: submitted_at, **attrs)
    s.save!(validate: false)
    s.viva_turns.create!(role: :student, status: :ok, content: 'answer') if answered
    s
  end

  def policy(user = @john)
    Viva::StartPolicy.new(@problem.reload, user)
  end

  test "a blank limit falls back to the site default and counts answered sessions only" do
    set_grader_config("viva.practice_daily_start_limit", 2)
    session_for(answered: false)
    session_for
    assert_equal 2, policy.limit
    assert_equal 1, policy.counted_today
    assert_equal 1, policy.starts_left
    assert_nil policy.refusal

    session_for
    assert_match(/Daily practice limit reached for 'viva_problem' \(2\/day\)/, policy.refusal)
  end

  test "a missing or non-positive site default falls back to 3" do
    set_grader_config("viva.practice_daily_start_limit", 0)
    assert_equal 3, Viva::StartPolicy.daily_limit_for(@problem)
  end

  test "sessions from before today do not count" do
    @problem.update!(viva_daily_limit: 1)
    session_for(submitted_at: Time.zone.now.beginning_of_day - 1.hour)
    assert_equal 0, policy.counted_today
    assert_nil policy.refusal
  end

  test "limit 0 refuses outside contest mode and allows one counted session in contest mode" do
    @problem.update!(viva_daily_limit: 0)
    assert policy.contest_only?
    assert_equal 0, policy.limit
    assert_match(/can only be taken during a contest/, policy.refusal)

    set_grader_config("system.mode", "contest")
    assert_equal 1, policy.limit
    assert_nil policy.refusal
    session_for
    assert_match(/You have used your attempt for 'viva_problem'.*ask a proctor/, policy.refusal)
  end

  test "in contest mode a limit above 1 says how many attempts were used" do
    @problem.update!(viva_daily_limit: 2)
    set_grader_config("system.mode", "contest")
    2.times { session_for }
    assert_match(/You have used all 2 of today's attempts/, policy.refusal)
  end

  test "a granted session stops counting" do
    @problem.update!(viva_daily_limit: 1)
    s = session_for
    assert policy.refusal
    s.grant_viva_retake!(by: users(:admin))
    assert_equal 0, policy.counted_today
    assert_nil policy.refusal
  end

  test "test-drives never count" do
    @problem.update!(viva_daily_limit: 1)
    session_for(test_drive: true)
    assert_nil policy.refusal
  end

  test "admins are unlimited" do
    @problem.update!(viva_daily_limit: 1)
    admin = users(:admin)
    2.times { session_for(admin) }
    assert_nil policy(admin).limit
    assert_nil policy(admin).starts_left
    assert_nil policy(admin).refusal
  end

  test "restart is allowed only when the student could start again" do
    @problem.update!(viva_daily_limit: 1)
    answered = session_for
    refute policy.restart_allowed?(answered)

    peek = session_for(answered: false)
    assert policy.restart_allowed?(peek), "a session with no answer never counted"

    drive = session_for(test_drive: true)
    assert policy.restart_allowed?(drive)

    @problem.update!(viva_daily_limit: 2)
    assert policy.restart_allowed?(answered)
  end
end
