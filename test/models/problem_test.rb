require "test_helper"

class ProblemTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid problem fixture" do
    assert problems(:prob_add).valid?
  end

  test "name must be present" do
    problem = Problem.new(full_name: "Test")
    assert_not problem.valid?
    assert problem.errors[:name].any?
  end

  test "name must be unique" do
    problem = Problem.new(name: "add", full_name: "Duplicate")
    assert_not problem.valid?
    assert problem.errors[:name].any?
  end

  test "name must match format" do
    problem = Problem.new(name: "bad name!", full_name: "Test")
    assert_not problem.valid?
    assert problem.errors[:name].any?
  end

  test "name allows brackets and dashes" do
    problem = Problem.new(name: "test-prob[1](A)", full_name: "Test", live_dataset: datasets(:ds_add))
    assert problem.valid?
  end

  test "full_name must be present" do
    problem = Problem.new(name: "testprob")
    assert_not problem.valid?
    assert problem.errors[:full_name].any?
  end

  # --- Enums ---

  test "compilation_type enum" do
    prob = problems(:prob_add)
    assert prob.respond_to?(:self_contained?)
    assert prob.respond_to?(:with_managers?)
  end

  test "task_type enum" do
    prob = problems(:prob_add)
    assert prob.respond_to?(:batch?)
  end

  # --- Scopes ---

  test "available scope returns only available problems" do
    available = Problem.available
    assert_includes available, problems(:prob_add)
    assert_not_includes available, problems(:prob_sub)
  end

  test "group_submittable_by_user returns problems in user groups" do
    john = users(:john)
    problems = Problem.group_submittable_by_user(john.id)
    # john is in group_a, prob_add is available and in group_a
    assert_includes problems, problems(:prob_add)
    # prob_sub is not available, so should not be included
    assert_not_includes problems, problems(:prob_sub)
  end

  # --- Methods ---

  test "long_name returns formatted name" do
    prob = problems(:prob_add)
    assert_equal "[add] add_full_name", prob.long_name
  end

  test "get_next_dataset_name generates sequential names" do
    prob = problems(:prob_add)
    # prob_add already has ds_add named "Dataset 1"
    name = prob.get_next_dataset_name("Dataset")
    assert_match(/Dataset/, name)
  end

  # --- Associations ---

  test "problem has datasets" do
    prob = problems(:prob_add)
    assert_includes prob.datasets, datasets(:ds_add)
  end

  test "problem has testcases" do
    prob = problems(:prob_add)
    assert prob.testcases.count >= 2
  end

  test "problem has tags through problems_tags" do
    prob = problems(:prob_add)
    assert_includes prob.tags, tags(:tag_easy)
  end

  test "problem has submissions" do
    prob = problems(:prob_add)
    assert prob.submissions.count > 0
  end

  # --- permitted_lang ordering ---
  # set_language picks the fallback language as `permitted.first`, so the order
  # returned here must be deterministic (ascending id), not the typed order or
  # the name-index order MySQL happens to return.

  test "get_permitted_lang_as_ids returns all ids ascending when blank" do
    prob = problems(:prob_add)
    prob.update!(permitted_lang: "")
    ids = prob.get_permitted_lang_as_ids
    assert_equal Language.count, ids.size
    assert_equal ids.sort, ids, "blank permitted_lang must return all ids in ascending order"
  end

  test "get_permitted_lang_as_ids returns an explicit set in ascending id order" do
    prob = problems(:prob_add)
    langs = [languages(:Language_c), languages(:Language_cpp), languages(:Language_java)]
    # list the names deliberately in descending-id order
    prob.update!(permitted_lang: langs.sort_by(&:id).reverse.map(&:name).join(" "))
    assert_equal langs.map(&:id).sort, prob.get_permitted_lang_as_ids,
                 "permitted ids must come back ascending regardless of the order they were typed in"
  end
end
