require 'test_helper'

# End-to-end (offline half): fixture bundle -> CmsDumpConverter -> real
# ProblemImporter -> DB. The live-server half is the operator gate (Task 6).
class CmsCloneIntegrationTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/cms_bundles/eatingfish_mini')

  test 'converted bundle imports with both datasets, fields, and blobs intact' do
    Dir.mktmpdir('cms_clone_int_') do |tmp|
      staging = File.join(tmp, 'staging')
      conv = Converters::CmsDumpConverter.new
      res = conv.convert(FIXTURE, staging)
      assert_equal [], res[:errors]

      pi = ProblemImporter.new
      log = pi.import_dataset_from_dir(staging, conv.problem_meta[:name],
                                       full_name: conv.problem_meta[:full_name])
      assert_kind_of Array, log
      assert_empty pi.errors

      problem = Problem.find_by(name: 'eatingfish_mini')
      assert problem, 'problem not created'
      assert_equal 'กินปลา mini', problem.full_name
      assert problem.with_managers?
      assert_equal 'eatingfish.cpp', problem.submission_filename
      assert_equal false, problem.available, 'clone must land unavailable'
      assert problem.statement.attached?
      assert problem.attachment.attached?
      assert_equal 'starter.zip', problem.attachment.filename.to_s

      live = problem.live_dataset
      assert_equal 1.0, live.time_limit
      assert_equal 512, live.memory_limit
      assert live.st_group_min?
      assert_equal 'grader.cpp', live.main_filename
      assert_equal %w[eatingfish.h grader.cpp],
                   live.managers.map { |m| m.filename.to_s }.sort
      tcs = live.testcases.order(:num)
      assert_equal %w[1-01 2-01 2-02], tcs.map(&:code_name)
      assert_equal [30, 70, 70], tcs.map(&:weight)
      assert_equal [1, 2, 2], tcs.map(&:group)
      assert_equal "1 2\n", tcs.first.inp_file.download
      assert_equal "3\n", tcs.first.ans_file.download

      rev2 = problem.datasets.find_by(name: 'rev2')
      assert rev2, 'additional dataset not imported'
      refute_equal problem.live_dataset_id, rev2.id
      assert rev2.st_sum?
      assert_equal 2.0, rev2.time_limit
      assert_equal 256, rev2.memory_limit
      assert_equal ['1-01'], rev2.testcases.map(&:code_name)
      assert_equal [1], rev2.testcases.map(&:weight)
    end
  end
end
