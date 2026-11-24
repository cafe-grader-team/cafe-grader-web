require "test_helper"

# The two text-rendering helpers behind the viva transcript. Students type C++
# there, so `<` and `>` must survive verbatim: the browser must never be
# allowed to read `vector<int>` as a tag (which the default sanitizer then
# strips, showing the student a history that is not what they typed).
class ApplicationHelperTest < ActionView::TestCase
  test "simple_format_escaped keeps template brackets literally" do
    html = simple_format_escaped("I used vector<int> v; and a<b && c>d\nsecond line")
    assert_includes html, "vector&lt;int&gt; v;"
    assert_includes html, "a&lt;b &amp;&amp; c&gt;d"
    assert_includes html, "<br />second line"
    assert_no_match %r{<int>|<b>}, html
    assert html.html_safe?
  end

  test "simple_format_escaped neutralizes script tags" do
    html = simple_format_escaped("x <script>alert(1)</script> y")
    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_no_match %r{<script}, html
  end

  test "simple_format_escaped still splits paragraphs" do
    html = simple_format_escaped("one\n\ntwo")
    assert_equal "<p>one</p>\n\n<p>two</p>", html
  end

  test "safe_markdown keeps template brackets in prose and code" do
    assert_includes safe_markdown("Use vector<int> here, or a < b."), "vector&lt;int&gt; here, or a &lt; b."
    assert_includes safe_markdown("Use `vector<pair<int,int>>` here."), "<code class=\"prettyprint\">vector&lt;pair&lt;int,int&gt;&gt;</code>"
  end

  test "safe_markdown escapes raw HTML instead of executing it, autolinks intact" do
    html = safe_markdown("before <script>alert(1)</script> after <http://example.com>")
    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_no_match %r{<script}, html
    assert_includes html, '<a href="http://example.com">http://example.com</a>'
  end

  # Markdown reads `<scheme:...>` as a link, and Redcarpet accepted any scheme:
  # `std::vector<std::set<int>>` showed as `std::vectorstd::set<int>` (a link
  # to "std::set<int"), and `<javascript:...>` or `[x](javascript:...)` became
  # a clickable script link in model-written text. Only web, mail and
  # relative links may become links; anything else stays literal text.
  test "safe_markdown links only safe schemes, so std:: templates stay text" do
    assert_includes safe_markdown("pick std::vector<std::set<int>> here"), "std::vector&lt;std::set&lt;int&gt;&gt; here"
    html = safe_markdown("[a](javascript:alert(1)) <javascript:alert(2)> <data:text/html,x>")
    assert_no_match %r{href="(javascript|data):}i, html
    assert_includes html, "&lt;javascript:alert(2)&gt;"
    html = safe_markdown("<https://example.com> [rel](/main/list) <mailto:a@b.c> www.x.com")
    assert_includes html, '<a href="https://example.com">https://example.com</a>'
    assert_includes html, '<a href="/main/list">rel</a>'
    assert_includes html, '<a href="mailto:a@b.c">a@b.c</a>'
    assert_includes html, '<a href="http://www.x.com">www.x.com</a>'
  end

  # GitHub #50 vector 2. Staff-authored markdown — announcements, hints,
  # submission comments — may carry the HTML those authors really use (links
  # that open a new tab, font size/colour, tables, images; every one of these
  # is in production announcement bodies) but never script, frames or event
  # handlers, which would run in every reader's browser.
  test "sanitized_markdown keeps the staff HTML in use: new-tab links, font, tables, images" do
    html = sanitized_markdown(<<~MD)
      <ul><li><a href="/doc.pdf" target="_blank">doc</a></li></ul>
      <font size=+3 color=red>late</font>
      <table border=1><tr><td>a</td><td>b</td></tr></table>
      <img src="/a.png" width=100%>
    MD
    assert_includes html, '<a href="/doc.pdf" target="_blank">doc</a>'
    assert_includes html, '<font size="+3" color="red">late</font>'
    assert_match %r{<table border="1">.*<td>a</td><td>b</td>.*</table>}m, html
    assert_includes html, '<img src="/a.png" width="100%">'
    assert html.html_safe?
  end

  test "sanitized_markdown strips script, iframe and event handlers but keeps the text" do
    html = sanitized_markdown(%(hello <script>alert(1)</script><iframe src="https://x.test/clock"></iframe><a href="/x" target="_blank" onclick="alert(2)">x</a><img src=x onerror=alert(3)>))
    assert_no_match %r{<script|<iframe|onclick|onerror}, html
    assert_includes html, 'hello'
    assert_includes html, '<a href="/x" target="_blank">x</a>'
  end

  test "sanitized_markdown still renders markdown" do
    html = sanitized_markdown("- [a](/a.pdf)\n\n**bold**")
    assert_includes html, '<li><a href="/a.pdf">a</a></li>'
    assert_includes html, '<strong>bold</strong>'
  end

  test "sanitized_html applies the same allow-list without a markdown pass" do
    html = sanitized_html(%(<font color=red>now</font> <script>alert(1)</script>))
    assert_includes html, '<font color="red">now</font>'
    assert_no_match %r{<script|<p>}, html
    assert html.html_safe?
  end
end
