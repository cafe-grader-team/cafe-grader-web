require "test_helper"

class Replay::ReplayDiffTest < ActiveSupport::TestCase
  D = Replay::ReplayDiff

  test "identical grading is exact" do
    r = D.classify("PPP-P", 80, "PPP-P", 80)
    assert_equal :exact, r[:verdict]
    assert_empty r[:positions]
  end

  test "only T->P and x->P upgrades are benign" do
    r = D.classify("TxP", 33, "PPP", 100)
    assert_equal :benign, r[:verdict]
    assert_equal 2, r[:positions].size
    assert r[:positions].all? { |p| p[:kind] == :benign }
  end

  test "P->T (or any other change) is a mismatch" do
    r = D.classify("PPP", 100, "PPT", 66)
    assert_equal :mismatch, r[:verdict]
    assert_equal({ i: 2, from: "P", to: "T", kind: :mismatch }, r[:positions].first)
  end

  test "wrong-answer flip is a mismatch, not benign" do
    r = D.classify("P-P", 66, "PPP", 100)   # -  ->  P is NOT in the benign set
    assert_equal :mismatch, r[:verdict]
  end

  test "different lengths are structural" do
    r = D.classify("PPP", 100, "PP", 100)
    assert_equal :structural, r[:verdict]
    assert_match(/length differs/, r[:note])
  end

  test "a benign and a mismatch transition together roll up to mismatch" do
    r = D.classify("TP-", 50, "PPx", 50)   # T->P benign, but -->x is a mismatch
    assert_equal :mismatch, r[:verdict]
    kinds = r[:positions].map { |p| p[:kind] }
    assert_includes kinds, :benign
    assert_includes kinds, :mismatch
  end
end
