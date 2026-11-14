require 'test_helper'

# JudgeBase#isolate_options_by_lang is the per-language extra argv for
# isolate, applied to both the compile and the run sandbox (compiler.rb,
# evaluator.rb): the built-in options, then the host's own from worker.yml
# `isolate_options:`. Checker is the lightest class that mixes JudgeBase in.
class IsolateOptionsTest < ActiveSupport::TestCase
  setup do
    @judge = Checker.new('test-worker', 'test-box')
    @worker_conf = Rails.configuration.worker
    @saved = @worker_conf[:isolate_options]
    @worker_conf.delete(:isolate_options)
  end

  teardown do
    @saved.nil? ? @worker_conf.delete(:isolate_options) : @worker_conf[:isolate_options] = @saved
  end

  test "go raises the open-file limit above isolate's default of 64 (issue #40)" do
    opts = @judge.isolate_options_by_lang('go')
    assert_match(/--open-files=(\d+)/, opts)
    assert_operator opts[/--open-files=(\d+)/, 1].to_i, :>=, 512
    assert_includes opts, '--env=GOCACHE=/gocache'
  end

  test 'an unknown language gets no extra options' do
    assert_equal '', @judge.isolate_options_by_lang('brainfuck')
  end

  test 'without isolate_options in worker.yml a language gets exactly its built-in options' do
    assert_equal '-p -d /etc/alternatives', @judge.isolate_options_by_lang('java')
  end

  test "the host's isolate_options are added after the built-in ones, for that language only" do
    @worker_conf[:isolate_options] = { java: '-d /etc/java-21-openjdk' }
    assert_equal '-p -d /etc/alternatives -d /etc/java-21-openjdk', @judge.isolate_options_by_lang('java')
    assert_equal '-p -d /etc/alternatives', @judge.isolate_options_by_lang('rust')
  end

  test 'a host option for a language with no built-in options stands alone' do
    @worker_conf[:isolate_options] = { cpp: '-d /opt/extra' }
    assert_equal '-d /opt/extra', @judge.isolate_options_by_lang('cpp')
  end

  test 'the compile sandbox and the run sandbox both carry the host options' do
    @worker_conf[:isolate_options] = { java: '-d /etc/java-21-openjdk' }
    evaluator = Evaluator.new('test-worker', 'test-box')
    assert_includes evaluator.run_isolate_args('java').join(' '), '-d /etc/java-21-openjdk'
  end
end
