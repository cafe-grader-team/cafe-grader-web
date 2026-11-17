require "test_helper"

# Rails' simple_format runs its HTML sanitizer by default, which reads C++
# like `vector<int>` as a tag and drops it: the reader sees `vector`. That hid
# brackets in the viva transcript (fixed rev 2078), then again in the viva
# grade feedback and in student messages (revs 2287, 2288), each time on a
# view the previous fix had not looked at.
#
# Plain text goes through ApplicationHelper#simple_format_escaped (escape,
# then paragraphs); markdown through one of the three markdown helpers (see
# CLAUDE.md, "Three markdown renderers"). If this test fails, switch the
# listed line to one of those.
class NoBareSimpleFormatTest < ActiveSupport::TestCase
  test "no view or helper calls bare simple_format" do
    hits = Dir[Rails.root.join("app/{views,helpers}/**/*.{haml,erb,rb}")].flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("#", "-#")                                          # Ruby / HAML comment
        next if path.end_with?("application_helper.rb") && line.include?("sanitize: false")  # simple_format_escaped itself
        "#{path.delete_prefix("#{Rails.root}/")}:#{i + 1}: #{line.strip}" if line =~ /\bsimple_format\b/
      end
    end
    assert_empty hits, "bare simple_format sanitizes away `<int>`; use simple_format_escaped:\n#{hits.join("\n")}"
  end
end
