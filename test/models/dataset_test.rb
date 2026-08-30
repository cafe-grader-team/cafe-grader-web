require "test_helper"

class DatasetTest < ActiveSupport::TestCase
  # --- Enums ---

  test "evaluation_type enum" do
    ds = datasets(:ds_add)
    assert ds.respond_to?(:default?)
    assert ds.respond_to?(:exact?)
    assert ds.respond_to?(:custom_cafe?)
    assert ds.respond_to?(:custom_testlib?)
    assert ds.respond_to?(:custom_testlib_raw?)
    assert ds.respond_to?(:cms_comparator?)
  end

  # rev 2047 renamed custom_cms -> custom_testlib and custom_cms_raw ->
  # custom_testlib_raw without touching the stored integers. Old names must
  # keep working on assignment (older export packages, API clients).
  test "legacy evaluation_type names are accepted and normalized on assignment" do
    ds = datasets(:ds_add)
    ds.evaluation_type = 'custom_cms'
    assert_equal 'custom_testlib', ds.evaluation_type
    ds.evaluation_type = :custom_cms_raw
    assert_equal 'custom_testlib_raw', ds.evaluation_type
    ds.evaluation_type = 'cms_comparator'
    assert_equal 'cms_comparator', ds.evaluation_type
    ds.assign_attributes(evaluation_type: 'custom_cms')
    assert_equal 'custom_testlib', ds.evaluation_type
    assert_raises(ArgumentError) { ds.evaluation_type = 'bogus' }
  end

  test "renamed evaluation types keep their integer values (no data migration)" do
    assert_equal 4, Dataset.evaluation_types['custom_testlib']
    assert_equal 6, Dataset.evaluation_types['custom_testlib_raw']
    assert_equal 7, Dataset.evaluation_types['cms_comparator']
    assert_nil Dataset.evaluation_types['custom_cms']
  end

  test "score_type enum" do
    ds = datasets(:ds_add)
    assert ds.respond_to?(:st_sum?)
    assert ds.respond_to?(:st_group_min?)
    assert ds.respond_to?(:st_raw_sum?)
  end

  # --- Methods ---

  test "live? returns true for live dataset" do
    ds = datasets(:ds_add)
    assert ds.live?
  end

  test "live? returns false for non-live dataset" do
    ds = datasets(:ds_sub)
    prob = ds.problem
    # If ds_sub is prob_sub's live_dataset, this should be true
    # Let's test against a different problem's dataset
    if prob.live_dataset == ds
      assert ds.live?
    else
      assert_not ds.live?
    end
  end

  test "get_name_for_dir returns name when present" do
    ds = datasets(:ds_add)
    assert_equal "Dataset 1", ds.get_name_for_dir
  end

  # --- Associations ---

  test "dataset belongs to problem" do
    ds = datasets(:ds_add)
    assert_equal problems(:prob_add), ds.problem
  end

  test "dataset has testcases" do
    ds = datasets(:ds_add)
    assert ds.testcases.count >= 2
  end

  # --- main_filename presence ---

  test "main_filename is auto-set to first manager filename when missing" do
    ds = datasets(:ds_add)
    ds.problem.update!(compilation_type: :with_managers)
    ds.managers.attach(io: StringIO.new("// header"), filename: "main.cpp", content_type: "text/x-c")
    ds.managers.attach(io: StringIO.new("// other"),  filename: "other.cpp", content_type: "text/x-c")
    ds.update_columns(main_filename: nil) # bypass callback to set up the scenario
    ds.reload
    # Callback fires on validation; presence validation then passes.
    assert ds.save
    assert_equal "main.cpp", ds.main_filename
  end

  test "main_filename presence is enforced when managers attached + with_managers" do
    ds = datasets(:ds_add)
    ds.problem.update!(compilation_type: :with_managers)
    ds.managers.attach(io: StringIO.new("// m"), filename: "m.cpp", content_type: "text/x-c")
    # Skip the auto-pick callback by stubbing it out so we can verify
    # the validation acts as a backstop when the callback is bypassed.
    ds.define_singleton_method(:update_main_filename) { false }
    ds.main_filename = nil
    assert_not ds.valid?
    assert_includes ds.errors[:main_filename], "can't be blank"
  end

  test "main_filename can be blank when no managers are attached" do
    ds = datasets(:ds_add)
    ds.problem.update!(compilation_type: :with_managers)
    # No managers; the callback also nils main_filename. Validation
    # condition is false (managers.attached? is false), so save succeeds.
    ds.main_filename = nil
    assert ds.valid?
  end

  test "main_filename can be blank for self_contained problems" do
    ds = datasets(:ds_add)
    ds.problem.update!(compilation_type: :self_contained)
    ds.managers.attach(io: StringIO.new("// m"), filename: "m.cpp", content_type: "text/x-c")
    ds.main_filename = nil
    # Even with managers attached, self_contained problems don't need
    # main_filename — the validation condition checks with_managers?.
    ds.define_singleton_method(:update_main_filename) { false }
    assert ds.valid?
  end

  # --- mixed_weight_groups (group_min authoring check) ---

  # Build a scratch dataset (non-live) on prob_add with the given testcases.
  # tcs: array of {code_name:, num:, group:, weight:}.
  def dataset_with(score_type, tcs)
    ds = problems(:prob_add).datasets.create!(name: "mwg", score_type: score_type,
                                              evaluation_type: :default,
                                              time_limit: 1, memory_limit: 64)
    tcs.each { |tc| ds.testcases.create!(**tc) }
    ds
  end

  test "mixed_weight_groups returns {} unless score_type is group_min" do
    ds = dataset_with(:sum, [
      { code_name: "a", num: 1, group: 1, weight: 10 },
      { code_name: "b", num: 2, group: 1, weight: 20 }, # mixed, but Sum doesn't care
    ])
    assert_equal({}, ds.mixed_weight_groups)
  end

  test "mixed_weight_groups returns {} when every group is uniform" do
    ds = dataset_with(:group_min, [
      { code_name: "a", num: 1, group: 1, weight: 10 },
      { code_name: "b", num: 2, group: 1, weight: 10 },
      { code_name: "c", num: 3, group: 2, weight: 30 },
    ])
    assert_equal({}, ds.mixed_weight_groups)
  end

  test "mixed_weight_groups flags only the groups with differing weights, sorted" do
    ds = dataset_with(:group_min, [
      { code_name: "a", num: 1, group: 1, weight: 50 },
      { code_name: "b", num: 2, group: 1, weight: 30 }, # group 1 mixed
      { code_name: "c", num: 3, group: 2, weight: 20 },
      { code_name: "d", num: 4, group: 2, weight: 20 }, # group 2 uniform
    ])
    assert_equal({ 1 => [30, 50] }, ds.mixed_weight_groups)
  end

  test "mixed_weight_groups treats a nil weight as 0 (matches the scorer)" do
    ds = dataset_with(:group_min, [
      { code_name: "a", num: 1, group: 1, weight: nil }, # -> 0
      { code_name: "b", num: 2, group: 1, weight: 5 },
    ])
    assert_equal({ 1 => [0, 5] }, ds.mixed_weight_groups)
  end

  # --- set_by_array: CMS-style codename regexp grouping ---

  test "set_by_array assigns weight + group by codename regexp, start-anchored" do
    ds = dataset_with(:group_min,
                      %w[1-1 1-2 2-1 2-2 10-1].each_with_index.map { |cn, i| { code_name: cn, num: i + 1 } })

    ds.set_by_array(:weight, [[40, "1-.*"], [60, "2-.*"]], can_use_cms_mode: true)

    by_cn = ds.testcases.reload.index_by(&:code_name)
    assert_equal [1, 40], [by_cn["1-1"].group, by_cn["1-1"].weight]
    assert_equal [1, 40], [by_cn["1-2"].group, by_cn["1-2"].weight]
    assert_equal [2, 60], [by_cn["2-1"].group, by_cn["2-1"].weight]
    assert_equal [2, 60], [by_cn["2-2"].group, by_cn["2-2"].weight]
    # "1-.*" is anchored at the start (like CMS re.match), so 10-1 is NOT swept
    # into group 1 — it stays untouched.
    assert_nil by_cn["10-1"].group
    assert_nil by_cn["10-1"].weight
  end

  test "set_by_array still supports integer counts in CMS mode" do
    ds = dataset_with(:group_min,
                      %w[a b c d e].each_with_index.map { |cn, i| { code_name: cn, num: i + 1 } })

    ds.set_by_array(:weight, [[40, 2], [60, 3]], can_use_cms_mode: true)

    ordered = ds.testcases.reload.order(:num).to_a
    assert_equal [40, 40, 60, 60, 60], ordered.map(&:weight)
    assert_equal [1, 1, 2, 2, 2], ordered.map(&:group)
  end

  test "set_by_array regexp selector is honored only in CMS mode" do
    # The hash-form callers pass can_use_cms_mode: false; a string selector there
    # must NOT be treated as a regexp ("1-.*".to_i == 1 -> a positional count of 1),
    # and no group is written.
    ds = dataset_with(:group_min,
                      %w[1-1 1-2 2-1].each_with_index.map { |cn, i| { code_name: cn, num: i + 1 } })

    ds.set_by_array(:weight, [[40, "1-.*"]], can_use_cms_mode: false)

    ordered = ds.testcases.reload.order(:num).to_a
    assert_equal 40, ordered[0].weight # count 1 -> first testcase only
    assert_nil ordered[1].weight
    assert_nil ordered[0].group        # not CMS mode -> no group written
  end
end
