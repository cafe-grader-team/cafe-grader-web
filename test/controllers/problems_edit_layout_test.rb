require "test_helper"

# /problems/:id/edit has two layouts — regular: Detail card (tabs) + Dataset
# card; viva: ONE form spanning a Detail card and a Viva Exam card — and
# `update` redraws the whole body when a save crosses the viva boundary.
class ProblemsEditLayoutTest < ActionDispatch::IntegrationTest
  setup { sign_in_as("admin", "admin") }

  test "viva problem: one form spans both cards; no dataset frame, no tabs" do
    prob = problems(:prob_viva)
    get edit_problem_path(prob)
    assert_response :success
    assert_select "#problem-edit turbo-frame#problem form#edit_problem_#{prob.id}", count: 1 do
      assert_select "textarea#problem_viva_prompt", count: 1
      assert_select "textarea#problem_description", count: 1
      assert_select "select#problem_grounding_material_ids", count: 1
      assert_select "select#problem_conduct_tag_ids", count: 1
      assert_select "input#problem_viva_soft_cap", count: 1
      assert_select "input#problem_name", count: 1
      assert_select "input[type=submit]", count: 2          # one per card
    end
    assert_select "h5", text: "Viva Exam"
    assert_select "[data-viva-exam-toggle-target=showForViva]", count: 1   # the right card, not hidden
    assert_select "[data-viva-exam-toggle-target=showForViva].d-none", count: 0
    assert_select "turbo-frame#dataset_select", count: 0
    assert_select ".nav-tabs", count: 0
    assert_select "#description", count: 0
    assert_select "#hint", count: 0
  end

  test "regular problem: tabs, viva inputs inline and hidden, dataset card beside" do
    prob = problems(:prob_add)
    get edit_problem_path(prob)
    assert_response :success
    assert_select ".nav-tabs .nav-link", count: 3
    assert_select "turbo-frame#dataset_select", count: 1
    assert_select "form#edit_problem_#{prob.id}" do
      assert_select "#general [data-viva-exam-toggle-target=showForViva].d-none textarea#problem_viva_prompt", count: 1
      assert_select "#description textarea#problem_description", count: 1
    end
    assert_select "h5", text: "Viva Exam", count: 0
  end

  test "an ordinary save replaces only the :problem frame" do
    prob = problems(:prob_viva)
    patch problem_path(prob), params: { problem: { viva_soft_cap: 9, permitted_lang: [""] } }, as: :turbo_stream
    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="problem">}, response.body
    assert_no_match %r{target="problem-edit"}, response.body
    assert_equal 9, prob.reload.viva_soft_cap
  end

  test "switching a regular problem to viva redraws the whole body in the viva layout" do
    prob = problems(:prob_add)
    patch problem_path(prob), params: { problem: { compilation_type: "viva_exam", permitted_lang: [""] } }, as: :turbo_stream
    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="problem-edit">}, response.body
    assert_match %r{Viva Exam}, response.body
    assert_no_match %r{turbo-frame id="dataset_select"}, response.body
    assert prob.reload.viva_exam?
  end

  test "switching a viva problem back redraws the whole body in the dataset layout" do
    prob = problems(:prob_viva)
    patch problem_path(prob), params: { problem: { compilation_type: "self_contained", permitted_lang: [""] } }, as: :turbo_stream
    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="problem-edit">}, response.body
    assert_match %r{turbo-frame id="dataset_select"}, response.body
    assert_not prob.reload.viva_exam?
  end
end
