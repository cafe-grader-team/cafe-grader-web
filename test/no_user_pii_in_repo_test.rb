require "test_helper"

# This repo is public on GitHub and feeds the upstream project, so personal
# data of users never goes into it (CLAUDE.md, "User data stays out of this
# repo"; dae 2026-11-19). The DS Quiz 1 postmortem listed seven students'
# logins in doc/ and was public for two months before anyone noticed; history
# on GitHub cannot practically be scrubbed, so the check has to come before
# the commit.
#
# A login here is a Chula student ID: 10 digits, starting with the entry year
# (4x-7x in the Buddhist era). Any such number, or a student e-mail address,
# in a text file of the repo fails this test. If it fails: refer to the person
# by role or letter ("a TA", "student A") and put the real list in the private
# course-prep repo. A number that is genuinely not an ID goes in NOT_AN_ID.
class NoUserPiiInRepoTest < ActiveSupport::TestCase
  STUDENT_ID    = /\b[4-7]\d{9}\b/
  STUDENT_EMAIL = /\b[\w.+-]+@student\.chula\.ac\.th\b/i
  NOT_AN_ID     = %w[4294967295].freeze # 2**32 - 1 (MySQL LONGTEXT limit in an old migration)
  # The project's own writing: code, config, migrations, docs, specs, tests, plus top-level files.
  # Third-party code (vendor/, node_modules/, .yarn/) and local scratch (tmp/, log/) are not scanned.
  OWN_DIRS      = %w[app bin config db doc docs lib script spec swagger test].freeze
  TEXT_EXT      = %w[.md .txt .rb .rake .haml .erb .yml .yaml .json .js .scss .css .html .sql .sh .csv].freeze

  test "no student ID or student e-mail in the repo's text files" do
    root = Rails.root.to_s
    files = (Dir.glob("#{root}/{#{OWN_DIRS.join(',')}}/**/*") + Dir.glob("#{root}/*"))
              .select { |path| File.file?(path) && TEXT_EXT.include?(File.extname(path)) }
    hits = files.flat_map do |path|
      File.foreach(path).with_index.filter_map do |line, i|
        line = line.scrub
        found = line.scan(STUDENT_ID).reject { |n| NOT_AN_ID.include?(n) } + line.scan(STUDENT_EMAIL)
        "#{path.delete_prefix("#{root}/")}:#{i + 1}: #{found.join(', ')}" if found.any?
      end
    end
    assert_empty hits, "user data must not be committed to this public repo (CLAUDE.md, \"User data stays out of this repo\"):\n#{hits.join("\n")}"
  end
end
