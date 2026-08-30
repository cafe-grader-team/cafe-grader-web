require "test_helper"

class ReportHelperTest < ActionView::TestCase
  test "report_capped_names lists all names when under the cap" do
    html = report_capped_names(%w[Alpha Beta], drawer_id: "d")
    assert_includes html, "Alpha, Beta"
    refute_includes html, "more"
  end

  test "report_capped_names caps at 3 and appends a +N more drawer link" do
    html = report_capped_names(%w[Aa Bb Cc Dd Ee], drawer_id: "scope-drawer")
    assert_includes html, "Aa, Bb, Cc"
    refute_includes html, "Dd", "names past the cap are not shown inline"
    assert_includes html, "+2 more"
    assert_includes html, 'data-bs-toggle="offcanvas"'
    assert_includes html, 'data-bs-target="#scope-drawer"'
  end

  test "report_capped_names handles an empty list" do
    assert_includes report_capped_names([], drawer_id: "d"), "none"
  end
end
