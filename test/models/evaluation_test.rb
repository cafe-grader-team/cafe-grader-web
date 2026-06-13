require "test_helper"

class EvaluationTest < ActiveSupport::TestCase
  # --- Enum ---

  test "result enum has all expected values" do
    expected = %w[waiting correct wrong partial time_limit memory_limit crash unknown_error grader_error]
    expected.each do |val|
      assert_includes Evaluation.results.keys, val
    end
  end

  # --- Constants ---

  test "RESULT_CODE has correct length" do
    assert_equal Evaluation.results.count, Evaluation::RESULT_CODE.length
  end

  test "COLOR_CLASS has correct length" do
    assert_equal Evaluation.results.count, Evaluation::COLOR_CLASS.length
  end

  # --- Methods ---

  test "result_enum_to_code converts correct to P" do
    assert_equal "P", Evaluation.result_enum_to_code("correct")
  end

  test "result_enum_to_code converts wrong to -" do
    assert_equal "-", Evaluation.result_enum_to_code("wrong")
  end

  test "result_enum_to_code converts time_limit to T" do
    assert_equal "T", Evaluation.result_enum_to_code("time_limit")
  end

  test "result_enum_to_code returns empty for invalid result" do
    assert_equal "", Evaluation.result_enum_to_code("nonexistent")
  end

  test "class_for_result returns CSS class" do
    css = Evaluation.class_for_result("correct")
    assert_includes css, "success"
  end

  test "result_as_word returns code character" do
    eval_record = evaluations(:eval_add1_tc1)
    assert_equal "P", eval_record.result_as_word
  end

  # --- Associations ---

  test "evaluation belongs to submission and testcase" do
    eval_record = evaluations(:eval_add1_tc1)
    assert_equal submissions(:add1_by_admin), eval_record.submission
    assert_equal testcases(:tc_add_1), eval_record.testcase
  end
end
