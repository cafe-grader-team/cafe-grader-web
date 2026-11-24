require "test_helper"
require Rails.root.join("db/migrate/20261121150100_seed_llm_assist_spending_limit_configuration")

# The help-deduction rule and lookups (spec 2026-11-21 deduction cap and
# spending limit). Hints and AI help lower a problem's full score; a contest
# may cap the total (deduction cap) and limit AI spending (spending limit).
class HelpDeductionTest < ActiveSupport::TestCase
  # set_grader_config changes the cached settings; the row change rolls back
  # with the test, the cache does not
  teardown { reset_grader_config_cache }

  def contest_with(cap: nil, limit: nil)
    Contest.new(deduction_cap: cap, assist_spending_limit: limit)
  end

  test "deduction adds hints and AI help, up to the cap" do
    assert_equal 25, HelpDeduction.deduction(10, 15, nil)
    assert_equal 30, HelpDeduction.deduction(20, 25, 30)
    assert_equal 15, HelpDeduction.deduction(10, 5, 30)
    assert_equal 0,  HelpDeduction.deduction(nil, nil, 30)
  end

  test "final score is the raw score under the reduced full score, never below 0" do
    assert_equal 70, HelpDeduction.final_score(90, 20, 25, 30)
    assert_equal 90, HelpDeduction.final_score(90, 0, 0, 30)
    assert_equal 55, HelpDeduction.final_score(90, 20, 25, nil)
    assert_equal 0,  HelpDeduction.final_score(100, 60, 60, nil)
    assert_equal 0,  HelpDeduction.final_score(nil, 0, 0, nil)
  end

  test "parse_cap accepts whole numbers 0..100 only" do
    assert_equal 30, HelpDeduction.parse_cap("30")
    assert_equal 0,  HelpDeduction.parse_cap("0")
    assert_equal 100, HelpDeduction.parse_cap(" 100 ")
    [nil, "", "abc", "150", "-5", "1.5", "30abc"].each do |junk|
      assert_nil HelpDeduction.parse_cap(junk), "#{junk.inspect} must mean no cap"
    end
  end

  test "the site spending limit comes from the setting, 100 by default" do
    assert_equal 100, HelpDeduction.site_spending_limit
    set_grader_config('system.llm_assist_spending_limit', 150)
    assert_equal 150, HelpDeduction.site_spending_limit
  end

  test "cap_for is the one shared cap, else none" do
    assert_equal 30, HelpDeduction.cap_for([contest_with(cap: 30), contest_with(cap: 30)])
    assert_nil HelpDeduction.cap_for([contest_with(cap: 30), contest_with(cap: 20)])
    assert_nil HelpDeduction.cap_for([contest_with(cap: nil), contest_with(cap: 30)])
    assert_nil HelpDeduction.cap_for([])
    assert HelpDeduction.caps_disagree?([contest_with(cap: nil), contest_with(cap: 30)])
    assert_not HelpDeduction.caps_disagree?([contest_with(cap: 30), contest_with(cap: 30)])
    assert_not HelpDeduction.caps_disagree?([])
  end

  test "spending_limit_for takes the largest, a blank one counting as the site setting" do
    assert_equal 100, HelpDeduction.spending_limit_for([])
    assert_equal 150, HelpDeduction.spending_limit_for([contest_with(limit: nil), contest_with(limit: 150)])
    assert_equal 100, HelpDeduction.spending_limit_for([contest_with(limit: nil), contest_with(limit: 50)])
    assert_equal 50,  HelpDeduction.spending_limit_for([contest_with(limit: 50)])
  end

  test "a budget counts only what is left under the cap" do
    b = HelpDeduction::Budget.new(cap: 30, hint_lost: 10, ai_lost: 15, ai_spent: 15, spending_limit: 100)
    assert_equal 25, b.lost
    assert_equal 25, b.counted
    assert_equal 5,  b.counts(10)
    assert_not b.at_cap?
    full = HelpDeduction::Budget.new(cap: 30, hint_lost: 20, ai_lost: 20)
    assert_equal 30, full.counted
    assert_equal 0,  full.counts(10)
    assert full.at_cap?
    assert_equal 10, HelpDeduction::Budget.new(cap: nil, hint_lost: 20, ai_lost: 20).counts(10)
  end

  test "contest validates the cap 0..100 and a non-negative spending limit" do
    c = contests(:contest_a)
    [101, -1, 1.5].each do |bad|
      c.deduction_cap = bad
      assert_not c.valid?, "cap #{bad} must be refused"
    end
    [nil, 0, 30, 100].each do |ok|
      c.deduction_cap = ok
      assert c.valid?, "cap #{ok.inspect} must be accepted"
    end
    c.assist_spending_limit = -1
    assert_not c.valid?
    [nil, 0, 250].each do |ok|
      c.assist_spending_limit = ok
      assert c.valid?, "limit #{ok.inspect} must be accepted"
    end
  end

  test "the spending-limit seed migration is idempotent and keeps an operator's value" do
    GraderConfiguration.where(key: 'system.llm_assist_spending_limit').delete_all
    SeedLlmAssistSpendingLimitConfiguration.new.up
    row = GraderConfiguration.find_by(key: 'system.llm_assist_spending_limit')
    assert_equal '100', row.value
    assert_equal 'integer', row.value_type
    row.update!(value: '150')
    SeedLlmAssistSpendingLimitConfiguration.new.up
    assert_equal 1, GraderConfiguration.where(key: 'system.llm_assist_spending_limit').count
    assert_equal '150', row.reload.value
  end

  # --- final review fixes ---

  test "losses reuses the caller's window instead of looking the contests up again" do
    set_grader_config('system.mode', 'contest')
    james = users(:james)
    range = james.active_contests_range
    ids = [problems(:prob_add).id]
    assert_queries_count(2) { HelpDeduction.losses(james, ids, range: range) }
  end

  test "a budget in a running contest carries its cap, name, losses and spending limit" do
    set_grader_config('system.mode', 'contest')
    c = contests(:contest_a)
    c.update!(deduction_cap: 30, assist_spending_limit: 150)
    sub = submissions(:add1_by_james).dup
    sub.assign_attributes(submitted_at: c.start + 5.minutes, number: nil)
    sub.save!(validate: false)
    sub.comments.create!(user: users(:james), kind: 'llm_assist', status: 'ok', cost: 15, title: 't', body: 'b')
    comments(:hint_for_add).comment_reveals.create!(user: users(:james)).update_columns(created_at: c.start + 6.minutes)
    b = HelpDeduction.budget(users(:james), problems(:prob_add))
    assert_equal 30, b.cap
    assert_equal 'contest_a', b.contest_name
    assert_equal 16.5, b.lost
    assert_equal 15, b.ai_spent
    assert_equal 150, b.spending_limit
  end
end
