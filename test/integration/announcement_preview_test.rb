require "test_helper"

# Announcement body previews (main-page cards and the admin announcements
# table) render the body as real markdown, clamped with CSS, instead of the
# old stripped-text teaser — which both flattened all formatting and
# double-escaped entities (the browser showed literal `&amp;` / `&quot;`).
class AnnouncementPreviewTest < ActionDispatch::IntegrationTest
  LONG_BODY = <<~MD
    Reference documents for the exam, with a **bold** intro.

    ### Section One
    * [Slides & codes](/doc/slides.pdf)
    * Place it under "build/libs/runscript"

    #{'Filler sentence to push the preview past the clamp threshold. ' * 5}
  MD

  setup do
    @long  = Announcement.create!(title: 'Long markdown announcement', author: 'staff',
                                  body: LONG_BODY, published: true, frontpage: false, contest_only: false)
    @short = Announcement.create!(title: 'Short note', author: 'staff',
                                  body: 'Just a **short** note.', published: true, frontpage: false, contest_only: false)
  end

  test "card renders markdown, clamps long body, and links to a matching modal" do
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success

    card = "#announcement-#{@long.id}"
    # real rendered markdown in the preview, not stripped text
    assert_select "#{card} .announcement-preview h3", text: 'Section One'
    assert_select "#{card} .announcement-preview strong", text: 'bold'
    assert_select "#{card} .announcement-preview.announcement-preview-clamped"
    # Read More targets a modal that exists and contains the full rendered body
    assert_select %(#{card} a[data-bs-target="#announcementModal-#{@long.id}"]), text: /Read More/
    assert_select "#announcementModal-#{@long.id} .modal-body h3", text: 'Section One'
  end

  test "short body renders markdown without clamp, Read More, or modal" do
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success

    card = "#announcement-#{@short.id}"
    assert_select "#{card} .announcement-preview strong", text: 'short'
    assert_select "#{card} .announcement-preview-clamped", false
    assert_select "#announcementModal-#{@short.id}", false
  end

  test "special characters are not double-escaped on the card" do
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success

    # regression: the old markdown -> strip_tags -> unescape chain emitted
    # &amp;amp; / &amp;quot; in the HTML source, which the browser displayed
    # as literal '&amp;' and '&quot;' text
    assert_no_match(/&amp;amp;|&amp;quot;/, response.body)
    # the & in the link text is escaped exactly once in the HTML source
    assert_match(/Slides &amp; codes/, response.body)
  end

  test "admin announcements index uses the same markdown preview" do
    sign_in_as("admin", "admin")
    get announcements_path
    assert_response :success

    assert_select ".announcement-preview h3", text: 'Section One'
    assert_select %(a[data-bs-target="#announcementModal-#{@long.id}"]), text: /Read More/
    assert_select "#announcementModal-#{@long.id} .modal-body h3", text: 'Section One'
    assert_no_match(/&amp;amp;|&amp;quot;/, response.body)
  end

  # GitHub #50 vector 2: an editor's announcement must not run script in every
  # visitor's browser, while the HTML editors actually use keeps working
  # (production bodies carry new-tab PDF links, font colour, tables).
  XSS_BODY = %(Read <a href="/doc.pdf" target="_blank">the doc</a> <font color="red">now</font><script>alert(1)</script><iframe src="https://x.test/"></iframe>)

  test "main-page card strips script and frames from an announcement but keeps new-tab links and font" do
    ann = Announcement.create!(title: 'x', author: 'staff', body: XSS_BODY, published: true, frontpage: false, contest_only: false)
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success
    card = css_select("#announcement-#{ann.id}").first.to_html
    assert_no_match %r{<script|<iframe}, card
    assert_includes card, '<a href="/doc.pdf" target="_blank">the doc</a>'
    assert_includes card, '<font color="red">now</font>'
  end

  test "announcement show page sanitizes the body the same way" do
    ann = Announcement.create!(title: 'x', author: 'staff', body: XSS_BODY, published: true, frontpage: false, contest_only: false)
    sign_in_as("admin", "admin")
    get announcement_path(ann)
    assert_response :success
    page = css_select("#main-content").first.to_html   # the layout has its own <script> tags
    assert_no_match %r{<script|<iframe}, page
    assert_includes page, '<a href="/doc.pdf" target="_blank">the doc</a>'
  end

  test "navbar strip sanitizes an on_nav_bar announcement" do
    Announcement.create!(title: 'x', author: 'staff', body: XSS_BODY, published: true, on_nav_bar: true, contest_only: false)
    sign_in_as("john", "hello")
    get list_main_path
    assert_response :success
    strip = css_select("p.navbar-text").map(&:to_html).join
    assert_no_match %r{<script|<iframe}, strip
    assert_includes strip, '<font color="red">now</font>'
  end
end
