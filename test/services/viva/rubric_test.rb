require "test_helper"

class Viva::RubricTest < ActiveSupport::TestCase
  BRIEFING = <<~MD
    # Examiner briefing — The Missing `operator=`

    Concept viva.

    # Rubric

    Weights sum to 100.

    - implicit_assignment_diagnosis (20): knows line (1) invokes the copy assignment.
    - `memory_picture_and_leak` (20): leak and aliasing.
    * consequence_analysis (25.5): double delete.
    - correct_fix (24.5): operator= done right.
    - rule_of_three_generalization (10): names the Rule of Three.

    # Notes for the examiner

    - not_an_item (99): outside the rubric section
  MD

  test "parses the items of the Rubric section only" do
    r = Viva::Rubric.parse(BRIEFING)
    assert_equal({"implicit_assignment_diagnosis" => 20, "memory_picture_and_leak" => 20,
                  "consequence_analysis" => 25.5, "correct_fix" => 24.5,
                  "rule_of_three_generalization" => 10}, r.weights)
    assert r.readable?
    assert r.sums_to_100?
  end

  test "a briefing without a Rubric list is unreadable" do
    refute Viva::Rubric.parse("# Briefing\nNo rubric here.").readable?
    refute Viva::Rubric.parse("# Rubric\nBe fair.").readable?
    refute Viva::Rubric.parse(nil).readable?
  end

  test "a C++ #include line is not a heading" do
    r = Viva::Rubric.parse("# Rubric\n- a (40): x\n#include <vector>\n- b (60): y\n")
    assert_equal({"a" => 40, "b" => 60}, r.weights)
  end

  test "weights that do not sum to 100 are reported" do
    r = Viva::Rubric.parse("# Rubric\n- a (20): x\n- b (30): y\n")
    assert r.readable?
    refute r.sums_to_100?
    assert_equal 50, r.sum
  end

  test "a grade that adds up has no problems" do
    w = {"a" => 20, "b" => 80}
    assert_equal [], Viva::Rubric.grade_problems(w, {a: 15, b: 60}.to_json, 75)
    assert_equal [], Viva::Rubric.grade_problems(w, {a: {score: 15}, b: "60"}.to_json, 75.0)
  end

  test "grade problems: above maximum, wrong sum, names off the rubric, unreadable" do
    w = {"a" => 20, "b" => 80}
    assert_equal ["above maximum: a 30/20"], Viva::Rubric.grade_problems(w, {a: 30, b: 60}.to_json, 90)
    assert_equal ["items sum to 75, total is 70"], Viva::Rubric.grade_problems(w, {a: 15, b: 60}.to_json, 70)
    assert_equal ["not in the rubric: c", "missing: b", "items sum to 15, total is 75"],
                 Viva::Rubric.grade_problems(w, {a: 10, c: 5}.to_json, 75)
    assert_equal ["rubric scores unreadable"], Viva::Rubric.grade_problems(w, "not json", 10)
    assert_equal ["a rubric score is not a number"], Viva::Rubric.grade_problems(w, {a: "x", b: 1}.to_json, 1)
  end
end
