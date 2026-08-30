# test/services/submission_repair/gate_test.rb
require 'test_helper'

class SubmissionRepair::GateTest < ActiveSupport::TestCase
  def gate(orig, rep, lines: 2, chars: 20)
    SubmissionRepair::Gate.evaluate(original: orig, repaired: rep,
                                    budget_lines: lines, budget_chars: chars)
  end

  test "identical sources -> no_change" do
    r = gate("int main(){}\n", "int main(){}\n")
    assert_equal :no_change, r.verdict
    assert_equal 0, r.changed_lines
  end

  test "whitespace-only differences are normalized away" do
    r = gate("int main(){}  \r\n\n\n", "int main(){}\n")
    assert_equal :no_change, r.verdict
  end

  test "single-char fix on one line" do
    r = gate("printf(\"%d \", x);\n", "printf(\"%d\\n\", x);\n")
    assert_equal :accepted, r.verdict
    assert_equal 1, r.changed_lines
    assert_operator r.changed_chars, :<=, 3
    assert_includes r.patch, '-printf'
    assert_includes r.patch, '+printf'
  end

  test "modified line counts once (paired), insert and delete count each" do
    orig = "a\nb\nc\n"
    rep  = "a\nB\nc\nd\n"        # b->B modified, d inserted
    r = gate(orig, rep, lines: 5, chars: 50)
    assert_equal 2, r.changed_lines
    assert_equal 1 + 1, r.changed_chars  # levenshtein(b,B)=1 + len(d)=1
  end

  test "line budget exceeded -> over_budget with true measurements" do
    orig = (1..10).map { |i| "line#{i}" }.join("\n")
    rep  = (1..10).map { |i| "LINE#{i}" }.join("\n")
    r = gate(orig, rep, lines: 2, chars: 1000)
    assert_equal :over_budget, r.verdict
    assert_equal 10, r.changed_lines
  end

  test "char budget exceeded independently of line budget" do
    r = gate("short\n", "a completely rewritten very long line\n", lines: 2, chars: 10)
    assert_equal :over_budget, r.verdict
    assert_equal 1, r.changed_lines
    assert_operator r.changed_chars, :>, 10
  end

  test "deleting a line costs its full length" do
    r = gate("keep\n0123456789\n", "keep\n", lines: 2, chars: 9)
    assert_equal :over_budget, r.verdict
    assert_equal 10, r.changed_chars
  end

  test "levenshtein ground truths" do
    assert_equal 0, SubmissionRepair::Gate.levenshtein('abc', 'abc')
    assert_equal 3, SubmissionRepair::Gate.levenshtein('', 'abc')
    assert_equal 1, SubmissionRepair::Gate.levenshtein('kitten', 'mitten')
    assert_equal 3, SubmissionRepair::Gate.levenshtein('kitten', 'sitting')
  end

  test "empty repaired source is a mass deletion, not a crash" do
    r = gate("a\nb\n", "", lines: 10, chars: 100)
    assert_equal :accepted, r.verdict
    assert_equal 2, r.changed_lines
  end
end
