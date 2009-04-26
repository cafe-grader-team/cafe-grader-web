require 'test/unit'
require 'rubygems'
require 'mocha'

require File.join(File.dirname(__FILE__),'../lib/import_helper')

class ImportHelperTest < Test::Unit::TestCase

  def setup
  end

  def teardown
  end

  def test_build_only_singleton_testruns
    testrun_info = build_testrun_info(3,['1','2','3'])
    assert_equal [[[1,'1']],[[2,'2']],[[3,'3']]], testrun_info, 'should build singleton testruns'
  end

  def test_build_only_singleton_testruns2
    testrun_info = build_testrun_info(4,['1','2','3','4'])
    assert_equal [[[1,'1']],[[2,'2']],[[3,'3']],[[4,'4']]], testrun_info, 'should build singleton testruns'
  end

  def test_build_testruns_when_testcases_defined_by_appending_alphabets
    testrun_info = build_testrun_info(4,['1a','1b','2','3a','3b','4'])
    assert_equal [[[1,'1a'],[2,'1b']],
                  [[3,'2']],
                  [[4,'3a'],[5,'3b']],
                  [[6,'4']]], testrun_info
  end

  def test_build_testruns_when_testcases_defined_by_appending_dashed_numbers
    testrun_info = build_testrun_info(4,['1-1','1-2','2','3-1','3-2','4'])
    assert_equal [[[1,'1-1'],[2,'1-2']],
                  [[3,'2']],
                  [[4,'3-1'],[5,'3-2']],
                  [[6,'4']]], testrun_info
  end
end
