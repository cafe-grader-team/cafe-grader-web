require 'test_helper'

# LangCheck (bin/rails engine:langcheck) compiles and runs a built-in program
# per language in the real sandbox. The sandbox itself cannot run in the test
# suite (no isolate on a CI box), so these cover what is decided before it
# starts, and that every program is wired to a compiler class.
class LangCheckTest < ActiveSupport::TestCase
  test 'a language with no compiler path in worker.yml is "not configured", not a failure' do
    r = LangCheck.new(compilers: {}).check('php')
    assert_equal :not_configured, r.verdict
    assert_match(/no compiler path: worker.yml has no `compiler: php:`/, r.detail)
  end

  test 'a compiler path that does not exist is "not configured"' do
    r = LangCheck.new(compilers: { javac: '/nonexistent/bin/javac' }).check('java')
    assert_equal :not_configured, r.verdict
    assert_match(%r{/nonexistent/bin/javac .* does not exist}, r.detail)
  end

  test 'a language langcheck has no program for is a failure that names the known ones' do
    r = LangCheck.new(compilers: {}).check('cobol')
    assert_equal :fail, r.verdict
    assert_match(/no program for 'cobol'/, r.detail)
  end

  test 'run checks each requested language once, in order' do
    results = LangCheck.new(compilers: {}).run(%w[java cpp])
    assert_equal %w[java cpp], results.map(&:language)
    assert(results.all? { |r| r.verdict == :not_configured })
  end

  test 'every built-in program has a compiler class of its own and a path key the sample config defines' do
    sample = File.read(Rails.root.join('config', 'worker.yml.SAMPLE'))
    LangCheck::PROGRAMS.each do |name, (key, source)|
      sub = LangCheck::Sub.new("langcheck_#{name}", source, LangCheck::Lang.new(name, name))
      assert_not_equal Compiler::Blank, Compiler.get_compiler(sub), "#{name} has no real compiler class"
      assert_match(/^    #{key}: /, sample, "worker.yml.SAMPLE has no `compiler: #{key}:` for #{name}")
    end
  end

  test 'each compiler class reads the path key langcheck checks for its language' do
    LangCheck::PROGRAMS.each do |name, (key, source)|
      sub = LangCheck::Sub.new("langcheck_#{name}", source, LangCheck::Lang.new(name, name))
      file = "app/engine/compiler/#{Compiler.get_compiler(sub).name.demodulize.underscore}.rb"
      assert_match(/\[:compiler\]\[:#{key}\]/, File.read(Rails.root.join(file)),
                   "#{name}: #{file} does not read worker[:compiler][:#{key}]")
    end
  end

  test 'the stand-in submission answers what the compiler classes ask of a submission and its problem' do
    sub = LangCheck::Sub.new('langcheck_java', 'src', LangCheck::Lang.new('java', 'java'))
    assert_same sub, sub.problem
    assert_equal false, sub.with_managers?
    assert_equal 'run.sh', sub.exec_filename(sub.language)
    assert_equal 'submission.java', sub.language.default_submission_filename
  end
end
