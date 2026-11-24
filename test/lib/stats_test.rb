require "test_helper"

class StatsTest < ActiveSupport::TestCase
  test "percentile on empty is nil" do
    assert_nil Stats.percentile([], 0.5)
  end

  test "percentile picks the nearest-rank value and does not require pre-sorting" do
    v = [5, 1, 4, 2, 3]
    assert_equal 1, Stats.percentile(v, 0.0)
    assert_equal 3, Stats.percentile(v, 0.5)
    assert_equal 5, Stats.percentile(v, 1.0)
  end

  test "p95 of 1..100 is 95" do
    assert_equal 95, Stats.percentile((1..100).to_a, 0.95)
  end

  test "mean" do
    assert_nil Stats.mean([])
    assert_in_delta 2.0, Stats.mean([1, 2, 3]), 0.001
  end
end
