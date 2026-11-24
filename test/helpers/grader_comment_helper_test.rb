require "test_helper"

class GraderCommentHelperTest < ActionView::TestCase
  teardown { Current.reset }

  test "a plain verdict string becomes one tile per testcase, no groups" do
    html = grader_comment_strip("PP-T")
    doc = Nokogiri::HTML.fragment(html)
    assert_equal 4, doc.css(".verdict-tile").size
    assert_equal 0, doc.css(".verdict-group").size
    assert_equal 1, doc.css(".verdict-run").size
    assert_equal %w[verdict-correct verdict-correct verdict-wrong verdict-time_limit],
                 doc.css(".verdict-tile").map { |t| t["class"].split.last }
    assert_equal "Test 3 of 4: Wrong Answer", doc.css(".verdict-tile")[2]["title"]
    assert_equal "PP-T", doc.at_css(".verdict-strip")["data-comment"]
  end

  test "bracket groups become boxes; loose tests stay bare; numbering runs across both" do
    html = grader_comment_strip("P[PPP-][TT]")
    doc = Nokogiri::HTML.fragment(html)
    assert_equal 7, doc.css(".verdict-tile").size
    assert_equal 2, doc.css(".verdict-group").size
    assert_equal 1, doc.css(".verdict-run").size, "the loose leading P"
    groups = doc.css(".verdict-group")
    assert_match(/\AGroup 1 of 2: 3\/4 passed\./, groups[0]["title"])
    assert_match(/\AGroup 2 of 2: 0\/2 passed\./, groups[1]["title"])
    assert_includes groups[0]["title"], "lowest score"
    assert_equal "Test 1 of 7: Correct", doc.css(".verdict-tile")[0]["title"]
    assert_equal "Test 5 of 7: Wrong Answer", doc.css(".verdict-tile")[4]["title"]
  end

  test "every letter in Evaluation::RESULT_CODE maps to a result class" do
    Evaluation::RESULT_CODE.each do |code|
      doc = Nokogiri::HTML.fragment(grader_comment_strip(code))
      klass = doc.at_css(".verdict-tile")["class"]
      assert_match(/\Averdict-tile verdict-[a-z_]+\z/, klass, "letter #{code.inspect} → #{klass}")
      refute_includes klass, "verdict-", "unmapped letter #{code.inspect}" if klass.end_with?("verdict-")
    end
  end

  test "free text, nested, unbalanced or empty-group comments fall back to the plain capped rendering" do
    ["No testcase", "x[x[uses 2579 parrots]]", "[[PP][PP]]", "[PP", "PP]", "[]P", "Grading timed out. Use Rejudge."].each do |c|
      doc = Nokogiri::HTML.fragment(grader_comment_strip(c))
      assert_equal 0, doc.css(".verdict-tile").size, c.inspect
      span = doc.at_css("span.grader-comment.grader-comment-capped")
      assert span, "plain span for #{c.inspect}"
      assert_equal " [#{c}]", span.text
    end
  end

  test "nil and blank render like today's empty brackets" do
    [nil, ""].each do |c|
      assert_equal %(<span class="grader-comment grader-comment-capped"> []</span>), grader_comment_strip(c)
    end
  end

  test "output is escaped" do
    doc = Nokogiri::HTML.fragment(grader_comment_strip("<b>bold</b>"))
    assert_equal 0, doc.css("b").size
    assert_includes grader_comment_strip("<b>x</b>"), "&lt;b&gt;"
  end
  # ---- per-user verdict display preference (User#verdict_display) ----

  def plain_viewer!
    Current.user = users(:john).tap { |u| u.verdict_display = 'plain' }
  end

  test "a viewer who prefers plain text gets the pre-4.5 uncapped rendering" do
    plain_viewer!
    doc = Nokogiri::HTML.fragment(grader_comment_strip("P[PP-]T"))
    assert_equal 0, doc.css(".verdict-tile").size
    span = doc.at_css("span.grader-comment.text-break")
    assert span, "expected the uncapped plain span"
    refute_includes span["class"], "grader-comment-capped"
    assert_equal " [P[PP-]T]", span.text
  end

  test "style: forces a rendering regardless of the viewer preference (profile samples)" do
    plain_viewer!
    assert Nokogiri::HTML.fragment(grader_comment_strip("PP", style: :tiles)).at_css(".verdict-tile"),
           "style: :tiles must render tiles for a plain-preference viewer"
    Current.reset
    assert Nokogiri::HTML.fragment(grader_comment_strip("PP", style: :plain)).at_css(".grader-comment.text-break"),
           "style: :plain must render plain with no viewer at all"
  end

  test "free-text comments keep the capped fallback even for plain-preference viewers" do
    plain_viewer!
    doc = Nokogiri::HTML.fragment(grader_comment_strip("No testcase"))
    assert doc.at_css("span.grader-comment.grader-comment-capped")
  end

  test "the client-side config carries the viewer's plain flag" do
    assert_includes verdict_strip_config_json, '"plain":false'
    plain_viewer!
    assert_includes verdict_strip_config_json, '"plain":true'
  end
end
