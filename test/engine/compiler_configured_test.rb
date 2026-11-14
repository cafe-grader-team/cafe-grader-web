require 'test_helper'

# Compiler#ensure_compiler_configured: a host with no compiler for a language
# must say so as a grader error, before any command is built. PHP and Pascal
# ran for years with an empty program name and blamed the student.
class CompilerConfiguredTest < ActiveSupport::TestCase
  Sub = Struct.new(:id, :language)
  Lang = Struct.new(:name, :pretty_name)

  setup do
    @compilers = Rails.configuration.worker[:compiler]
    @saved = @compilers.to_h
    @real = File.realpath('/bin/sh')
  end

  teardown do
    (@compilers.keys - @saved.keys).each { |key| @compilers.delete(key) }
    @saved.each { |key, value| @compilers[key] = value }
  end

  def check(language, pretty = nil)
    compiler = Compiler.new('test-worker', 'test-box')
    compiler.instance_variable_set(:@sub, Sub.new(42, Lang.new(language, pretty)))
    compiler.ensure_compiler_configured
  end

  test 'a language whose compiler path exists passes' do
    @compilers[:php] = @real
    assert_nothing_raised { check('php') }
  end

  test 'no line for the compiler is a grader error naming the key, with a message for the student' do
    @compilers.delete(:php)
    error = assert_raises(GraderError) { check('php', 'PHP') }
    assert_match(/No compiler for php on this judge host: worker.yml has no `compiler: php:` path/, error.message)
    assert_match(/engine:detect/, error.message)
    assert_equal 'The grader is not set up for PHP (this is not an error in your code; please tell the staff)',
                 error.message_for_user
    assert_equal 42, error.submission_id
  end

  test 'an empty path (the compiler is not installed, `which` printed nothing) is the same error' do
    @compilers[:pas] = ''
    assert_match(/no `compiler: pas:` path/, assert_raises(GraderError) { check('pas') }.message)
  end

  test 'a path that does not exist is a grader error naming the path' do
    @compilers[:javac] = '/nonexistent/bin/javac'
    error = assert_raises(GraderError) { check('java') }
    assert_match(%r{the `compiler: javac:` path /nonexistent/bin/javac does not exist}, error.message)
    assert_match(/not set up for java/, error.message_for_user)
  end

  test 'languages that need no program are never refused' do
    %w[archive text].each { |language| assert_nothing_raised { check(language) } }
  end

  test 'every compiler class reads only keys listed for its language, and every listed key is read' do
    Compiler::COMPILER_PATH_KEYS.each do |language, keys|
      klass = Compiler.get_compiler(Sub.new(1, Lang.new(language, nil)))
      code = File.read(Rails.root.join('app', 'engine', 'compiler', "#{klass.name.demodulize.underscore}.rb"))
      read = code.scan(/\[:compiler\]\[:(\w+)\]/).flatten.map(&:to_sym).uniq
      assert_equal keys.sort, read.sort, "#{language} (#{klass}): keys read by the class vs COMPILER_PATH_KEYS"
    end
  end

  test 'every language with a compiler class of its own is listed' do
    %w[cpp c python ruby java digital haskell php pas rust go postgres].each do |language|
      assert Compiler::COMPILER_PATH_KEYS.key?(language), "#{language} is missing from COMPILER_PATH_KEYS"
    end
  end
end
