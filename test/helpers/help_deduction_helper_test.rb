require "test_helper"

# The confirm boxes' block (hint reveal and AI help) and the problem list's
# line (spec 2026-11-21 deduction cap and spending limit).
class HelpDeductionHelperTest < ActionView::TestCase
  include HelpDeductionHelper

  def budget(**over)
    HelpDeduction::Budget.new(**{cap: 30, contest_name: "DS-Quiz-3", hint_lost: 10, ai_lost: 15,
                                 ai_spent: 100, spending_limit: 150}.merge(over))
  end

  test "under the cap: the cap, what was lost, and how much of this one counts" do
    text = help_budget_text(budget, cost: 10, kind: :hint)
    assert_includes text, "Contest `DS-Quiz-3` caps hint and AI deductions at 30 points per problem."
    assert_includes text, "Lost on this problem so far: 25 (hints 10, AI help 15)."
    assert_includes text, "This hint costs 10, but only 5 more counts (25 → 30)."
    assert_not_includes text, "AI help on this problem stops"
  end

  test "at the cap: nothing more counts" do
    text = help_budget_text(budget(hint_lost: 20, ai_lost: 15), cost: 10, kind: :hint)
    assert_includes text, "You have reached the cap, so this costs you nothing more."
    assert_not_includes text, "but only"
  end

  test "a charge that fits under the cap gets no extra line" do
    text = help_budget_text(budget(hint_lost: 0, ai_lost: 5), cost: 10, kind: :hint)
    assert_not_includes text, "but only"
    assert_not_includes text, "reached the cap"
  end

  test "without a cap only what was lost so far" do
    text = help_budget_text(budget(cap: nil, contest_name: nil), cost: 10, kind: :hint)
    assert_equal "Lost on this problem so far: 25 (hints 10, AI help 15).", text
  end

  test "the AI box also states the spending limit" do
    text = help_budget_text(budget, cost: 10, kind: :ai)
    assert_includes text, "This request costs 10, but only 5 more counts (25 → 30)."
    assert_includes text, "AI help on this problem stops once you have spent 150 points; you have spent 100."
  end

  test "the AI box adds nothing when the requester pays nothing" do
    assert_equal "", help_budget_text(budget, cost: 0, kind: :ai)
  end

  test "fractional hint costs print without float noise" do
    text = help_budget_text(budget(cap: nil, hint_lost: 1.5, ai_lost: 0), cost: 1.5, kind: :hint)
    assert_equal "Lost on this problem so far: 1.5 (hints 1.5, AI help 0).", text
  end

  test "the problem list's line" do
    assert_nil help_reduction_text(0, 0, 30, false)
    assert_equal "Full score reduced by 30 (capped; 45 before the cap)", help_reduction_text(30, 45, 30, false)
    assert_equal "Full score reduced by 20", help_reduction_text(20, 20, 30, false)
    assert_equal "Full score reduced by 45 (contest grading may cap this)", help_reduction_text(45, 45, nil, true)
  end
end
