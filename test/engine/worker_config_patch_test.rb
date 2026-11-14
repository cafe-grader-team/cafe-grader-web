require 'test_helper'

# WorkerConfigPatch is the text edit behind `bin/rails engine:detect WRITE=1`:
# it sets one `isolate_options: <language>:` line in the per-host worker.yml
# and must leave every other byte — ERB tags, comments, duplicate keys — alone.
class WorkerConfigPatchTest < ActiveSupport::TestCase
  BASE = <<~YML
    # cafe_grader judge configuration
    shared:
      compiler:
        cpp: /usr/bin/g++
        javac: <%= `which javac`.strip %>
      isolate_path: <%= `which isolate`.strip %>

      hosts:
        web: http://localhost

      # limits:
      #   checker_timeout: 30

    development:
      worker_id: 1

    production:
      worker_id: 1
  YML

  def parse(text)
    YAML.safe_load(ERB.new(text).result, aliases: true)
  end

  test 'a file with no section gets one at the end of shared:, and nothing else changes' do
    out = WorkerConfigPatch.apply(BASE, 'java', '-d /etc/java-21-openjdk')
    assert_equal({ 'java' => '-d /etc/java-21-openjdk' }, parse(out)['shared']['isolate_options'])
    # take the inserted block out again and the file is byte-for-byte the original
    block = /\n  # extra isolate options.*?\n  isolate_options:\n    java: "-d \/etc\/java-21-openjdk"\n/m
    assert_match block, out
    assert_equal BASE, out.sub(block, '')
    assert_operator out.index('isolate_options:'), :<, out.index('development:')
    assert_equal parse(BASE)['development'], parse(out)['development']
  end

  test 'applying the same value twice changes nothing the second time' do
    once = WorkerConfigPatch.apply(BASE, 'java', '-d /etc/java-21-openjdk')
    assert_equal once, WorkerConfigPatch.apply(once, 'java', '-d /etc/java-21-openjdk')
  end

  test 'an existing line for the language is replaced in place' do
    once = WorkerConfigPatch.apply(BASE, 'java', '-d /etc/java-17-openjdk')
    out = WorkerConfigPatch.apply(once, 'java', '-d /etc/java-21-openjdk')
    assert_equal({ 'java' => '-d /etc/java-21-openjdk' }, parse(out)['shared']['isolate_options'])
    assert_equal once.lines.size, out.lines.size
  end

  test "another language's hand-written line in the section is kept" do
    hand = BASE.sub("  hosts:\n", %(  isolate_options:\n    python: "-d /opt/venv"\n\n  hosts:\n))
    out = WorkerConfigPatch.apply(hand, 'java', '-d /etc/java-21-openjdk')
    assert_equal({ 'java' => '-d /etc/java-21-openjdk', 'python' => '-d /opt/venv' },
                 parse(out)['shared']['isolate_options'])
    assert_equal({ 'web' => 'http://localhost' }, parse(out)['shared']['hosts'])
  end

  test 'a nil value removes the line, and the section header when it was the only one' do
    once = WorkerConfigPatch.apply(BASE, 'java', '-d /etc/java-21-openjdk')
    out = WorkerConfigPatch.apply(once, 'java', nil)
    assert_nil parse(out)['shared']['isolate_options']
    assert_not_includes out, "  isolate_options:\n"
    assert_equal BASE, out, 'write then remove leaves the file as it was'

    two = WorkerConfigPatch.apply(once, 'python', '-d /opt/venv')
    kept = WorkerConfigPatch.apply(two, 'java', nil)
    assert_equal({ 'python' => '-d /opt/venv' }, parse(kept)['shared']['isolate_options'])
  end

  test 'removing from a file that has no section is a no-op' do
    assert_equal BASE, WorkerConfigPatch.apply(BASE, 'java', nil)
  end

  test 'the commented example in worker.yml.SAMPLE is not mistaken for the section' do
    sample = File.read(Rails.root.join('config', 'worker.yml.SAMPLE'))
    out = WorkerConfigPatch.apply(sample, 'java', '-d /etc/java-21-openjdk')
    assert_equal({ 'java' => '-d /etc/java-21-openjdk' }, parse(out)['shared']['isolate_options'])
    assert_includes out, "  # isolate_options:\n"
  end

  test 'a file with no shared: section is refused' do
    assert_raises(ArgumentError) { WorkerConfigPatch.apply("production:\n  worker_id: 1\n", 'java', '-d /x') }
  end

  test 'compiler_options is a section of its own next to isolate_options' do
    one = WorkerConfigPatch.apply(BASE, 'java', '-d /etc/java-21-openjdk')
    two = WorkerConfigPatch.apply(one, 'pas', '-Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/*', section: 'compiler_options')
    shared = parse(two)['shared']
    assert_equal({ 'java' => '-d /etc/java-21-openjdk' }, shared['isolate_options'])
    assert_equal({ 'pas' => '-Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/*' }, shared['compiler_options'])
    assert_equal parse(BASE)['production'], parse(two)['production']
    assert_equal one, WorkerConfigPatch.apply(two, 'pas', nil, section: 'compiler_options')
  end

  test 'an unknown section is refused' do
    assert_raises(ArgumentError) { WorkerConfigPatch.apply(BASE, 'java', '-d /x', section: 'hosts') }
  end

  test 'a missing compiler path is added to the existing compiler section, the other paths untouched' do
    out = WorkerConfigPatch.apply(BASE, 'php', '/usr/bin/php', section: 'compiler')
    compiler = parse(out)['shared']['compiler']
    assert_equal '/usr/bin/php', compiler['php']
    assert_equal parse(BASE)['shared']['compiler'], compiler.except('php')
    assert_equal BASE.lines.size + 1, out.lines.size
    assert_includes out, "    javac: <%= `which javac`.strip %>\n"
  end
end
